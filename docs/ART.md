# Иллюстрации: картинки, аватары, рубашка

Колода оформлена в духе Карачаево-Черкесии. На картинках (В, Д, К) — карачаевцы, русские и черкесы в традиционной одежде, у соперников — зверята в национальных костюмах, на рубашке — золотой орнамент из бараньих рогов, ромбов и двуглавого Эльбруса.

Все иллюстрации сгенерированы в [Higgsfield](https://higgsfield.ai) (проект «Деберц — КЧР») моделью **GPT Image 2.5**: качество `xhigh`, прозрачный фон, фигуры и рубашка — 2K, аватары — 1K. GPT Image 2.5 выбрана по итогам сравнения с Nano Banana Pro, Seedream 5.0 Pro и FLUX.2 max на одном и том же промпте: у неё точнее костюмы, срез ровно по поясу и настоящий прозрачный фон без вырезания. Иллюстрации созданы на платном тарифе Higgsfield, он разрешает коммерческое использование.

Если картинки нет в каталоге, приложение рисует прежний векторный вариант: убор с буквой, эмодзи, ромбическую сетку (`Deberc/Views/Cards/CardArt.swift`).

## Кто на картах

По числу — больше карачаевцев и русских, чуть меньше черкесов: 5 + 4 + 3.

| Масть | Король | Дама | Валет |
|---|---|---|---|
| ♠ пики | карачаевский старейшина: белая каракулевая папаха, чёрный чепкен с газырями, посох | карачаевка: шапочка с золотым шитьём, белая вуаль, синее бархатное платье | карачаевский джигит: серая папаха, красный башлык, камча |
| ♣ трефы | карачаевский бий с соколом | карачаевка с медным кумганом, изумрудное платье | кубанский казак: чуб из-под кубанки, синяя черкеска, нагайка |
| ♥ черви | казачий атаман с булавой | русская красавица в кокошнике с хлебом-солью | парень в косоворотке с гармонью |
| ♦ бубны | черкесский князь в белой черкеске с шашкой | черкешенка в высокой золотой шапке с вуалью | черкесский юноша с луком |

Соперники: Лёша 🐣 — войлочная карачаевская шляпа и чепкен; Катя 🦔 — павлопосадский платок; Саша 🐻 — картуз с цветком и косоворотка; Оля 🦊 — карачаевская шапочка с вуалью; Нина 🐱 — высокая черкесская шапка; Миша 🐺 — папаха и чепкен с газырями; Борис 🦉 — купеческий кафтан и очки; Вера 🦅 — белая шаль и серебряное ожерелье.

## Стиль (общая часть промптов)

Для фигур:

> Style: traditional 19th-century engraved playing-card illustration, like a hand-colored copperplate etching: crisp dark ink contour lines, fine engraved hatching and cross-hatching for shading, flat rich colors; palette of deep crimson, cobalt blue, emerald green, golden ochre, silver-grey, black and warm ivory. Composition: half-length figure from the waist up, front-facing, symmetrical and centered, cut off by the bottom edge of the image at waist level exactly like one half of a double-headed playing card; leave about 8% empty margin on the left and on the right, and about 4% empty margin above the headdress, so the hat and shoulders never touch the edges. Respectful, authentic depiction of North Caucasian traditional dress. No flags, no coats of arms, no religious symbols, no suit symbols, no letters, no text, no border, no frame, no card outline. Fully transparent background.

Поля — ≈8 % пустого места слева и справа, ≈4 % над убором: иначе на карте убор и плечи упираются в край портрета.

Перед стилем идёт `Court card figure for a classic playing card, the KING OF SPADES, in a Karachay-Cherkessia themed deck. Subject: …` — описание героя из таблицы, по-английски, с деталями костюма.

Для аватаров: `Round portrait avatar for a card game opponent in a Karachay-Cherkessia themed deck: <зверь и костюм>. Head and shoulders only, facing the viewer, centered, the head filling most of the frame.` плюс тот же стиль. Если зверь «очеловечивается» (так было с орлицей), помогает прямое `a BIRD, not a human … No human face`.

Рубашка (пропорция 2:3): золотой орнамент карачаевских войлочных ковров и черкесского золотого шитья — парные спирали бараньих рогов в ромбических медальонах, двойная рамка, пустой овал в центре с бисерным кольцом, маленький двуглавый Эльбрус сверху и снизу; только золотые линии на прозрачном фоне.

## Иконка

Валет пик (карачаевский джигит) поверх бордовой рубашки с орнаментом на зелёном сукне. Карты нарисованы по той же геометрии, что в игре (рамка с вырезом под индекс, «перевязь», медальон), из тех же портретов, поэтому иконка совпадает с картами за столом. Из четырёх вариантов этот лучше всех читается в размере 60 px.

    python3 scripts/icon/render_kchr_icon.py preview /tmp/icons   # все варианты для сравнения
    python3 scripts/icon/render_kchr_icon.py install jack-back     # AppIcon, AppIcon-Dark, AppIcon-Tinted

Если исходников Higgsfield под рукой нет, для `jack-back` хватит готовых картинок из каталога (только `prepare_art.py` с такой папкой потом не запускайте — он обработал бы уже готовые картинки ещё раз):

    mkdir -p art-raw
    cp Deberc/Assets.xcassets/Art/court-jack-spades.imageset/court-jack-spades.png \
       Deberc/Assets.xcassets/Art/back-ornament.imageset/back-ornament.png art-raw/

Основная иконка сохраняется без альфа-канала (иначе App Store отклонит сборку), тёмная — с прозрачным фоном, тонированная — оттенки серого на чёрном.

## Как заменить или добавить картинку

1. Сгенерируйте картинку с тем же стилем (1:1 для фигур и аватаров, 2:3 для рубашки, прозрачный фон).
2. Положите исходник в `art-raw/` с именем из каталога: `court-<jack|queen|king>-<spades|clubs|diamonds|hearts>`, `avatar-<id персонажа>`, `back-ornament`. Папка `art-raw/` в git не попадает.
3. Запустите `python3 scripts/prepare_art.py` (нужен `pip install Pillow`). Скрипт уменьшит картинку, «подтянет» прозрачность, сделает орнамент рубашки строго симметричным и сожмёт в палитру.

Как картинки встают на карту:

- портрет фигуры — квадрат справа от выреза под угловой индекс, низом под «перевязь» (`CardMetrics.courtPortraitRect`); нижняя половина карты — тот же портрет, повёрнутый на 180°;
- аватар вписывается в круг цвета персонажа;
- орнамент ложится на цветное поле рубашки (бордо, синяя, изумрудная), а медальон с «Д» — внутрь его овала. Если у нового орнамента овал другого размера, поправьте размер медальона в `CardBackPainter`.
