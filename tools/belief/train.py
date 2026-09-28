"""Обучение сети «чутья»: у кого сейчас какая невидимая карта.

Данные — файлы BeliefGen: запись = FEATURES байт признаков (значение × 255) и 32 байта ответов
(0 — у следующего по кругу, 1 — у следующего за ним, 2 — ни у кого, 255 — карта видна).
Сеть: FEATURES → H → H → 32 × 3 (ReLU). Вдвоём ответа «у следующего за ним» не бывает — он
закрывается маской. Итог — веса для DebercKit (`BeliefNet`): формат BLF1, float32, слой за слоем.

    python train.py data/*.bin --out belief.bin [--epochs 8] [--hidden 512]
"""
import argparse
import json
import math
import struct
import time

import numpy as np
import torch
import torch.nn.functional as F
from torch import nn

FEATURES = 709
CARDS = 32
CLASSES = 3
THREE_PLAYERS = 640      # номер признака «игра втроём»
PHASE = 641              # четыре признака фазы: торговля 1, торговля 2, обмен, розыгрыш


class Net(nn.Module):
    def __init__(self, hidden):
        super().__init__()
        self.l1 = nn.Linear(FEATURES, hidden)
        self.l2 = nn.Linear(hidden, hidden)
        self.l3 = nn.Linear(hidden, CARDS * CLASSES)

    def forward(self, x):
        h = F.relu(self.l1(x))
        h = F.relu(self.l2(h))
        logits = self.l3(h).view(-1, CARDS, CLASSES)
        two = (x[:, THREE_PLAYERS] < 0.5).view(-1, 1)
        return logits.masked_fill(torch.stack([torch.zeros_like(two), two, torch.zeros_like(two)], -1).expand_as(logits), -1e4)


def load(paths):
    parts = []
    for p in paths:
        raw = np.fromfile(p, dtype=np.uint8)
        parts.append(raw[: len(raw) // (FEATURES + CARDS) * (FEATURES + CARDS)].reshape(-1, FEATURES + CARDS))
    return parts


def split(parts, share):
    """Проверочная часть — хвост каждого файла: там другие партии, чем в начале."""
    train, val = [], []
    for a in parts:
        k = int(len(a) * (1 - share))
        train.append(a[:k])
        val.append(a[k:])
    return np.concatenate(train), np.concatenate(val)


def batch_loss(net, block, device):
    x = block[:, :FEATURES].to(device, non_blocking=True).float() / 255
    y = block[:, FEATURES:].to(device, non_blocking=True).long()
    logits = net(x)
    mask = y != 255
    loss = F.cross_entropy(logits[mask], y[mask], reduction="sum")
    return loss, int(mask.sum())


def prior_loss(block):
    """Для сравнения: ответ только по числу карт у каждого (без торговли и ходов)."""
    x = block[:, :FEATURES].astype(np.float32) / 255
    y = block[:, FEATURES:]
    unknown = x[:, : 32 * 20].reshape(-1, 32, 20)[:, :, 19]
    total = unknown.sum(1)
    counts = x[:, 640 + 61: 640 + 64] * 9            # карт на руке: я, следующий, следующий за ним
    three = x[:, THREE_PLAYERS] > 0.5
    next1 = counts[:, 1] - x[:, :640].reshape(-1, 32, 20)[:, :, 6].sum(1)   # минус точно известные
    next2 = np.where(three, counts[:, 2] - x[:, :640].reshape(-1, 32, 20)[:, :, 7].sum(1), 0)
    p = np.stack([next1, next2, np.maximum(total - next1 - next2, 0)], 1) / np.maximum(total, 1)[:, None]
    p = np.clip(p, 1e-4, 1)
    mask = y != 255
    rows = np.nonzero(mask)[0]
    return float(-np.log(p[rows, y[mask]]).mean())


def export(net, path):
    with open(path, "wb") as f:
        f.write(b"BLF1")
        layers = [net.l1, net.l2, net.l3]
        f.write(struct.pack("<I", len(layers)))
        for layer in layers:
            w = layer.weight.detach().float().cpu().numpy()      # [выход][вход]
            b = layer.bias.detach().float().cpu().numpy()
            f.write(struct.pack("<II", w.shape[1], w.shape[0]))
            f.write(w.astype("<f4").tobytes())
            f.write(b.astype("<f4").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", nargs="+")
    ap.add_argument("--out", default="belief.bin")
    ap.add_argument("--epochs", type=int, default=8)
    ap.add_argument("--hidden", type=int, default=512)
    ap.add_argument("--batch", type=int, default=4096)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--val", type=float, default=0.03)
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    parts = load(args.data)
    train, val = split(parts, args.val)
    print(f"device {device}; train {len(train):,} records, val {len(val):,}", flush=True)
    print(f"prior (counts only) val loss: {prior_loss(val[:200_000]):.4f}", flush=True)

    train_t = torch.from_numpy(train)
    val_t = torch.from_numpy(val)
    if device == "cuda":
        try:
            train_t = train_t.to(device)
            val_t = val_t.to(device)
        except RuntimeError:
            train_t = train_t.pin_memory()
    net = Net(args.hidden).to(device)
    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=1e-4)
    steps = args.epochs * math.ceil(len(train_t) / args.batch)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=steps, pct_start=0.05)
    amp = torch.autocast(device_type="cuda", dtype=torch.bfloat16) if device == "cuda" else torch.autocast(device_type="cpu", enabled=False)

    def evaluate():
        net.eval()
        total, count = 0.0, 0
        with torch.no_grad(), amp:
            for i in range(0, len(val_t), 16384):
                loss, n = batch_loss(net, val_t[i:i + 16384], device)
                total += float(loss)
                count += n
        net.train()
        return total / max(count, 1)

    started = time.time()
    history = []
    for epoch in range(args.epochs):
        order = torch.randperm(len(train_t), device=train_t.device)
        total, count = 0.0, 0
        for i in range(0, len(order), args.batch):
            block = train_t[order[i:i + args.batch]]
            with amp:
                loss, n = batch_loss(net, block, device)
            opt.zero_grad(set_to_none=True)
            (loss / max(n, 1)).backward()
            opt.step()
            sched.step()
            total += float(loss)
            count += n
        v = evaluate()
        history.append({"epoch": epoch + 1, "train": total / count, "val": v, "seconds": round(time.time() - started)})
        print(f"epoch {epoch + 1}: train {total / count:.4f}  val {v:.4f}  ({time.time() - started:.0f} s)", flush=True)
        export(net, args.out)
    with open(args.out + ".json", "w") as f:
        json.dump({"features": FEATURES, "hidden": args.hidden, "records": len(train), "history": history}, f, indent=1)
    print("saved", args.out)


if __name__ == "__main__":
    main()
