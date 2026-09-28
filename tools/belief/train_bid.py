"""Обучение сети заявок соперника (`BidPolicyNet`): что скажет сильный игрок в торговле.

Данные — файлы BidGen (и `.bids` от BeliefGen): FEATURES байт признаков (0/1) и байт ответа
(0 — пас, 1 — беру, 2…5 — назвать масть 0…3). Сеть: FEATURES → H → H → 6 (ReLU); недопустимые в этом
круге ответы закрываются маской. Итог — веса BLF2 для DebercKit.

    python train_bid.py data/bids*.bin --out bidpolicy.bin [--epochs 30] [--hidden 256] [--augment]
"""
import argparse
import itertools
import json
import math
import os
import struct
import time

import numpy as np
import torch
import torch.nn.functional as F
from torch import nn

FEATURES = 32 + 32 + 2 + 3 + 1 + 2 * 7 + 3
RECORD = FEATURES + 1
CLASSES = 6
VAL_SHARE = 0.05


class Net(nn.Module):
    def __init__(self, hidden):
        super().__init__()
        self.l1 = nn.Linear(FEATURES, hidden)
        self.l2 = nn.Linear(hidden, hidden)
        self.l3 = nn.Linear(hidden, CLASSES)

    def forward(self, x):
        return self.l3(F.relu(self.l2(F.relu(self.l1(x)))))


def allowed_mask(x):
    """Допустимые ответы: в 1-м круге — пас и «беру», во 2-м — пас и любая масть, кроме открытой."""
    round1 = x[:, 64] > 0.5
    open_suit = x[:, 32:64].view(-1, 4, 8).sum(2).argmax(1)
    m = torch.zeros(len(x), CLASSES, dtype=torch.bool, device=x.device)
    m[:, 0] = True
    m[:, 1] = round1
    for s in range(4):
        m[:, 2 + s] = ~round1 & (open_suit != s)
    return m


def suit_permutations():
    feats, labels = [], []
    for p in itertools.permutations(range(4)):
        inv = [p.index(s) for s in range(4)]
        f = list(range(FEATURES))
        for c in range(32):
            src = inv[c // 8] * 8 + c % 8
            f[c] = src
            f[32 + c] = 32 + src
        for r in range(2):
            base = 70 + r * 7 + 2
            for s in range(4):
                f[base + s] = base + inv[s]
        feats.append(f)
        labels.append([0, 1] + [2 + p[s] for s in range(4)])   # масть s переходит в p[s]
    return torch.tensor(feats), torch.tensor(labels)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", nargs="+")
    ap.add_argument("--out", default="bidpolicy.bin")
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--hidden", type=int, default=256)
    ap.add_argument("--batch", type=int, default=2048)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--augment", action="store_true")
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    parts = []
    for p in args.data:
        raw = np.fromfile(p, dtype=np.uint8)
        parts.append(raw[: len(raw) // RECORD * RECORD].reshape(-1, RECORD))
    train = np.concatenate([a[: int(len(a) * (1 - VAL_SHARE))] for a in parts])
    val = np.concatenate([a[int(len(a) * (1 - VAL_SHARE)):] for a in parts])
    print(f"device {device}; train {len(train):,}, val {len(val):,}", flush=True)
    counts = np.bincount(train[:, FEATURES], minlength=CLASSES)
    print("answers in train (pass, take, names):", counts.tolist(), flush=True)

    tx = torch.from_numpy(train[:, :FEATURES]).to(device).float()
    ty = torch.from_numpy(train[:, FEATURES]).to(device).long()
    vx = torch.from_numpy(val[:, :FEATURES]).to(device).float()
    vy = torch.from_numpy(val[:, FEATURES]).to(device).long()
    pf, pl = suit_permutations()
    pf, pl = pf.to(device), pl.to(device)

    net = Net(args.hidden).to(device)
    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=1e-4)
    steps = args.epochs * math.ceil(len(tx) / args.batch)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=steps, pct_start=0.05)

    def masked_loss(x, y):
        logits = net(x).masked_fill(~allowed_mask(x), -1e4)
        return F.cross_entropy(logits, y, reduction="sum"), logits

    started = time.time()
    history = []
    for epoch in range(args.epochs):
        order = torch.randperm(len(tx), device=device)
        total = 0.0
        for i in range(0, len(order), args.batch):
            idx = order[i:i + args.batch]
            x, y = tx[idx], ty[idx]
            if args.augment:
                pick = torch.randint(0, len(pf), (len(idx),), device=device)
                x = x.gather(1, pf[pick])
                y = pl[pick].gather(1, y.view(-1, 1)).view(-1)
            loss, _ = masked_loss(x, y)
            opt.zero_grad(set_to_none=True)
            (loss / len(idx)).backward()
            opt.step()
            sched.step()
            total += float(loss.detach())
        net.eval()
        with torch.no_grad():
            vloss, logits = masked_loss(vx, vy)
            acc = float((logits.argmax(1) == vy).float().mean())
        net.train()
        history.append({"epoch": epoch + 1, "train": total / len(tx), "val": float(vloss) / len(vx), "acc": acc})
        if epoch % 5 == 4 or epoch == args.epochs - 1:
            print(f"epoch {epoch + 1}: train {total / len(tx):.4f}  val {float(vloss) / len(vx):.4f}  acc {acc:.3f}"
                  f"  ({time.time() - started:.0f} s)", flush=True)
    with open(args.out, "wb") as f:
        f.write(b"BLF2")
        layers = [net.l1, net.l2, net.l3]
        f.write(struct.pack("<I", len(layers)))
        for layer in layers:
            w = layer.weight.detach().float().cpu().numpy()
            b = layer.bias.detach().float().cpu().numpy()
            f.write(struct.pack("<II", w.shape[1], w.shape[0]))
            f.write(w.astype("<f2").tobytes())
            f.write(b.astype("<f4").tobytes())
    with open(args.out + ".json", "w") as f:
        json.dump({"records": len(train), "history": history}, f, indent=1)
    print("saved", args.out)


if __name__ == "__main__":
    main()
