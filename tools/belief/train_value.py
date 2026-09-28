"""Обучение сети оценки позиции втроём (`ValueNet`): позиция с открытыми картами → итог сдачи.

Данные — файлы ValueGen: FEATURES байт признаков (значение × 255) и 3 × int16 — полезность сдачи × 2
для мест 0, 1, 2 относительно игрока. Сеть: FEATURES → H → H → 3 (ReLU), потери — Хьюбер на
полезности / 100. Итог — веса для DebercKit в формате BLF2 (как у train.py).

    python train_value.py data/v3*.bin --out value3.bin [--epochs 10] [--hidden 512] [--augment]
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

PER_CARD = 9
FEATURES = 32 * PER_CARD + 33
RECORD = FEATURES + 6
SCALE = 100.0
VAL_SHARE = 0.03


class Net(nn.Module):
    def __init__(self, hidden):
        super().__init__()
        self.l1 = nn.Linear(FEATURES, hidden)
        self.l2 = nn.Linear(hidden, hidden)
        self.l3 = nn.Linear(hidden, 3)

    def forward(self, x):
        return self.l3(F.relu(self.l2(F.relu(self.l1(x)))))


def load(paths):
    """Все файлы — в один массив без лишних копий; проверочная часть — хвост каждого файла."""
    sizes = [os.path.getsize(p) // RECORD for p in paths]
    data = np.empty((sum(sizes), RECORD), dtype=np.uint8)
    train, val = [], []
    offset = 0
    for p, n in zip(paths, sizes):
        with open(p, "rb") as f:
            view = memoryview(data[offset:offset + n]).cast("B")
            done = 0
            while done < len(view):
                got = f.readinto(view[done:])
                if not got:
                    break
                done += got
        k = int(n * (1 - VAL_SHARE))
        train.append(np.arange(offset, offset + k))
        val.append(np.arange(offset + k, offset + n))
        offset += n
    return data, np.concatenate(train), np.concatenate(val)


def suit_permutations():
    """Масти равноправны: переставляем блоки признаков карт (общие признаки от мастей не зависят)."""
    perms = []
    for p in itertools.permutations(range(4)):
        inv = [p.index(s) for s in range(4)]
        f = list(range(FEATURES))
        for c in range(32):
            src = inv[c // 8] * 8 + c % 8
            for k in range(PER_CARD):
                f[c * PER_CARD + k] = src * PER_CARD + k
        perms.append(f + list(range(FEATURES, RECORD)))    # цели не переставляются
    return torch.tensor(perms)


def unpack(block, device, perms=None):
    block = block.to(device, non_blocking=True)
    if perms is not None:
        block = block.gather(1, perms[torch.randint(0, len(perms), (len(block),), device=device)])
    x = block[:, :FEATURES].float() / 255
    raw = block[:, FEATURES:].to(torch.int32)
    u = (raw[:, 0::2] | (raw[:, 1::2] << 8))
    u = torch.where(u >= 32768, u - 65536, u).float() / 2 / SCALE
    return x, u


def export(net, path):
    with open(path, "wb") as f:
        f.write(b"BLF2")
        layers = [net.l1, net.l2, net.l3]
        f.write(struct.pack("<I", len(layers)))
        for layer in layers:
            w = layer.weight.detach().float().cpu().numpy()
            b = layer.bias.detach().float().cpu().numpy()
            f.write(struct.pack("<II", w.shape[1], w.shape[0]))
            f.write(w.astype("<f2").tobytes())
            f.write(b.astype("<f4").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", nargs="+")
    ap.add_argument("--out", default="value3.bin")
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--hidden", type=int, default=512)
    ap.add_argument("--batch", type=int, default=4096)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--wd", type=float, default=1e-4)
    ap.add_argument("--augment", action="store_true")
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    data, train_idx, val_idx = load(args.data)
    source = torch.from_numpy(data)
    if device == "cuda":
        free, _ = torch.cuda.mem_get_info()
        if data.nbytes < free - 3 * 2**30:
            source = source.to(device)
    train_t = torch.from_numpy(train_idx).to(source.device)
    val_t = source.index_select(0, torch.from_numpy(val_idx).to(source.device))
    print(f"device {device}; train {len(train_idx):,}, val {len(val_idx):,}; data on {source.device}", flush=True)
    _, vu = unpack(val_t[:200_000], device)
    print(f"val: std of outcome {float(vu.std() * SCALE):.1f} points (predicting 0 gives MSE {float((vu ** 2).mean()):.4f})", flush=True)

    perms = suit_permutations().to(device) if args.augment else None
    net = Net(args.hidden).to(device)
    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=args.wd)
    steps = args.epochs * math.ceil(len(train_idx) / args.batch)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=steps, pct_start=0.05)

    def evaluate():
        net.eval()
        total, count = 0.0, 0
        with torch.no_grad():
            for i in range(0, len(val_t), 16384):
                x, u = unpack(val_t[i:i + 16384], device)
                total += float(((net(x) - u) ** 2).sum())
                count += u.numel()
        net.train()
        return total / count

    started = time.time()
    history = []
    for epoch in range(args.epochs):
        order = train_t[torch.randperm(len(train_t), device=train_t.device)]
        total, count = 0.0, 0
        for i in range(0, len(order), args.batch):
            x, u = unpack(source.index_select(0, order[i:i + args.batch]), device, perms)
            loss = F.smooth_l1_loss(net(x), u, beta=1.0)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            sched.step()
            total += float(loss.detach()) * len(u)
            count += len(u)
        v = evaluate()
        history.append({"epoch": epoch + 1, "train": total / count, "val_mse": v, "seconds": round(time.time() - started)})
        print(f"epoch {epoch + 1}: train {total / count:.4f}  val MSE {v:.4f}  ({time.time() - started:.0f} s)", flush=True)
        export(net, args.out)
    torch.save(net.state_dict(), args.out + ".pt")
    with open(args.out + ".json", "w") as f:
        json.dump({"features": FEATURES, "hidden": args.hidden, "records": len(train_idx), "history": history}, f, indent=1)
    print("saved", args.out)


if __name__ == "__main__":
    main()
