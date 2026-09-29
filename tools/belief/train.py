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
import os
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
VAL_SHARE = 0.03


class Net(nn.Module):
    def __init__(self, hidden, dropout=0.0):
        super().__init__()
        self.l1 = nn.Linear(FEATURES, hidden)
        self.l2 = nn.Linear(hidden, hidden)
        self.l3 = nn.Linear(hidden, CARDS * CLASSES)
        self.drop = nn.Dropout(dropout)

    def forward(self, x):
        h = self.drop(F.relu(self.l1(x)))
        h = self.drop(F.relu(self.l2(h)))
        logits = self.l3(h).view(-1, CARDS, CLASSES)
        two = (x[:, THREE_PLAYERS] < 0.5).view(-1, 1)
        return logits.masked_fill(torch.stack([torch.zeros_like(two), two, torch.zeros_like(two)], -1).expand_as(logits), -1e4)


def suit_permutations():
    """Масти равноправны: перестановка мастей (вместе с козырем, заявками и «чистыми» мастями) даёт
    такую же правильную позицию. Индексы: признак i новой позиции = признак perm[i] старой."""
    import itertools
    feats, labels = [], []
    g = 32 * 20
    for p in itertools.permutations(range(4)):
        inv = [p.index(s) for s in range(4)]          # новая масть s была мастью inv[s]
        card = [inv[c // 8] * 8 + c % 8 for c in range(CARDS)]
        f = list(range(FEATURES))
        for c in range(CARDS):
            for k in range(20):
                f[c * 20 + k] = card[c] * 20 + k
        for base in (g + 5, g + 9):                      # козырь, масть открытой карты
            for s_ in range(4):
                f[base + s_] = base + inv[s_]
        for r in range(3):                               # названная во 2-м круге масть
            base = g + 19 + r * 8 + 2
            for s_ in range(4):
                f[base + s_] = base + inv[s_]
        for r in range(2):                               # «чистые» масти следующего и следующего за ним
            base = g + 53 + r * 4
            for s_ in range(4):
                f[base + s_] = base + inv[s_]
        feats.append(f)
        labels.append(card)
    return torch.tensor(feats), torch.tensor(labels)


RECORD = FEATURES + CARDS


def load(paths):
    """Все файлы — в один массив без лишних копий (данных может быть больше половины памяти).
    Проверочная часть — хвост каждого файла: там другие партии, чем в начале."""
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


def batch_loss(net, block, device, perms=None):
    x = block[:, :FEATURES].to(device, non_blocking=True)
    y = block[:, FEATURES:].to(device, non_blocking=True)
    if perms is not None:
        pick = torch.randint(0, len(perms[0]), (len(x),), device=device)
        x = x.gather(1, perms[0][pick])
        y = y.gather(1, perms[1][pick])
    x = x.float() / 255
    y = y.long()
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


def export(net, path, half=True):
    """BLF2: веса слоёв во float16 (вдвое меньше файл, точности хватает), сдвиги во float32.
    BLF1 — всё во float32."""
    with open(path, "wb") as f:
        f.write(b"BLF2" if half else b"BLF1")
        layers = [net.l1, net.l2, net.l3]
        f.write(struct.pack("<I", len(layers)))
        for layer in layers:
            w = layer.weight.detach().float().cpu().numpy()      # [выход][вход]
            b = layer.bias.detach().float().cpu().numpy()
            f.write(struct.pack("<II", w.shape[1], w.shape[0]))
            f.write(w.astype("<f2" if half else "<f4").tobytes())
            f.write(b.astype("<f4").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", nargs="+")
    ap.add_argument("--out", default="belief.bin")
    ap.add_argument("--epochs", type=int, default=8)
    ap.add_argument("--hidden", type=int, default=512)
    ap.add_argument("--batch", type=int, default=4096)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--dropout", type=float, default=0.0)
    ap.add_argument("--wd", type=float, default=1e-4)
    ap.add_argument("--augment", action="store_true", help="случайная перестановка мастей")
    ap.add_argument("--cpu-data", action="store_true", help="держать данные в памяти, а не в видеокарте")
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    data, train_idx, val_idx = load(args.data)
    print(f"device {device}; train {len(train_idx):,} records, val {len(val_idx):,}", flush=True)
    print(f"prior (counts only) val loss: {prior_loss(data[val_idx[:200_000]]):.4f}", flush=True)

    source = torch.from_numpy(data)          # общая с numpy память, без копии
    if device == "cuda":
        free, _ = torch.cuda.mem_get_info()
        if not args.cpu_data and data.nbytes < free - 3 * 2**30:   # помещается в видеокарту с запасом
            source = source.to(device)
    train_t = torch.from_numpy(train_idx).to(source.device)
    val_rows = torch.from_numpy(val_idx).to(source.device)
    print(f"data on {source.device} ({data.nbytes / 2**30:.1f} GB)", flush=True)
    net = Net(args.hidden, args.dropout).to(device)
    opt = torch.optim.AdamW(net.parameters(), lr=args.lr, weight_decay=args.wd)
    steps = args.epochs * math.ceil(len(train_idx) / args.batch)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=args.lr, total_steps=steps, pct_start=0.05)
    amp = torch.autocast(device_type="cuda", dtype=torch.bfloat16) if device == "cuda" else torch.autocast(device_type="cpu", enabled=False)

    val_t = source.index_select(0, val_rows)
    three_val = val_t[:, THREE_PLAYERS] > 127
    play_val = val_t[:, PHASE + 3] > 127
    groups = {"2p bid": ~three_val & ~play_val, "2p play": ~three_val & play_val,
              "3p bid": three_val & ~play_val, "3p play": three_val & play_val}

    def evaluate(detail=False):
        net.eval()
        result = {}
        with torch.no_grad(), amp:
            for name, rows in ([("all", None)] + list(groups.items()) if detail else [("all", None)]):
                data = val_t if rows is None else val_t[rows]
                total, count = 0.0, 0
                for i in range(0, len(data), 16384):
                    loss, n = batch_loss(net, data[i:i + 16384], device)
                    total += float(loss)
                    count += n
                result[name] = total / max(count, 1)
        net.train()
        return result if detail else result["all"]

    perms = None
    if args.augment:
        pf, pl = suit_permutations()
        perms = (pf.to(device), pl.to(device))
    started = time.time()
    history = []
    for epoch in range(args.epochs):
        order = train_t[torch.randperm(len(train_t), device=train_t.device)]
        total, count = 0.0, 0
        for i in range(0, len(order), args.batch):
            block = source.index_select(0, order[i:i + args.batch])
            with amp:
                loss, n = batch_loss(net, block, device, perms)
            opt.zero_grad(set_to_none=True)
            (loss / max(n, 1)).backward()
            opt.step()
            sched.step()
            total += float(loss.detach())
            count += n
        v = evaluate()
        history.append({"epoch": epoch + 1, "train": total / count, "val": v, "seconds": round(time.time() - started)})
        print(f"epoch {epoch + 1}: train {total / count:.4f}  val {v:.4f}  ({time.time() - started:.0f} s)", flush=True)
        export(net, args.out)
    detail = evaluate(detail=True)
    priors = {}
    val_np = data[val_idx]
    for name, rows in groups.items():
        sel = val_np[rows.cpu().numpy()]
        if len(sel):
            priors[name] = prior_loss(sel[:200_000])
    for name, v in detail.items():
        print(f"  val {name}: {v:.4f}" + (f"  (prior {priors[name]:.4f})" if name in priors else ""), flush=True)
    torch.save(net.state_dict(), args.out + ".pt")
    with open(args.out + ".json", "w") as f:
        json.dump({"features": FEATURES, "hidden": args.hidden, "records": len(train_idx), "history": history,
                   "val": detail, "prior": priors}, f, indent=1)
    print("saved", args.out)


if __name__ == "__main__":
    main()
