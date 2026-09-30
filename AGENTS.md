# Правила проекта (Godot 4.7, гонки)

## Godot

Бинарник Godot 4.7.2:
`/media/alexander/data/Godot_v4.7.2-stable_linux.x86_64`

Запуск скриптов и проверок headless:

```
/media/alexander/data/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tools/<script>.gd
```

Проверка, что здания/скайлайн не заезжают на трассу (PASS по всем трассам;
список трасс подхватывается из `assets/data/tracks/` автоматически):

```
/media/alexander/data/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tools/check_buildings.gd
```

## Мотоциклы (Road Rash)

- Гоночный транспорт — **реальные GLB-модели** (Sketchfab CC-BY) в
  `assets/bikes/<id>/body.glb` + процедурный сидящий райдер:
  `scripts/bike_visuals.gd` (рама/колёса — фолбэк), `scripts/rider.gd`
  (перс), данные — `BikeDef` в `assets/data/bikes/*.tres`
  (`model_path`, `model_yaw`, `rider_mount`). Пайплайн моделей —
  `tools/assetgen/process_bike.py` (+ `normalize_bike.py`).
- Ростер: `scrambler_01`, `sport_01`, `cruiser_01`, `super_01`, коп `cop_01`.
  Наклон/вилли — узел `Tilt` (bike-space), `BikeDef.lean_max`. Колёса
  крутятся, если у GLB есть ноды `wheel`/`tyre` (иначе статичны).
- Бой (Road Rash): Q/E — удар влево/вправо, F — пинок; здоровье в HUD,
  нокдаун → вайпаут (байк падает, райдер кувыркается) → возврат через 3 с.
  Логика в `scripts/race_bike.gd` (+ `rider.gd`), AI-агрессия — `AiDriver.decide_attack`.
- Урон: удары, а также столкновения (в машину — 10–40 по скорости, в стену —
  6–25; impact считается по скорости ДО `move_and_slide`, иначе dot≈0).
  ИИ-соперничество: резинка ±10% (`main.gd`), обгон на скорости
  (`AiDriver._blocker_much_slower`), мщение атакующему 4 с (`grudge`).
- Полиция (`scripts/police.gd`): коп появляется с задержкой (`POLICE_DELAY` env
  для теста) и преследует игрока; при скорости <6 м/с рядом с копом 2.5 с —
  BUSTED. Сбитый коп даёт бонус. Трафик (`scripts/traffic.gd`): 5 GLB-машин из
  `assets/data/traffic/` едут по полосам; быстрый удар = вайпаут.
  У каждой машины `model_yaw` в `assets/data/traffic/*.tres` должен разворачивать
  нос модели в −Z (иначе машина «едет боком»): проверка
  `tools/check_traffic_orient.gd` (PASS/FAIL), рендер-контроль —
  `tools/car_orient_shot.gd` (через `xvfb-run`, `CAR_ID=<id>` для одной модели).
- Проверки баланса/магазина/кампании/боя (должны быть PASS):
  `tools/check_tuning.gd`, `tools/check_shop.gd`, `tools/check_campaign.gd`,
  `tools/check_combat.gd`.
- Скриншот байка крупным планом: `tools/bike_close_shot.gd` (через `xvfb-run`;
  POSE=punch|kick|crash для боевых поз).

## Трассы

- Геометрия трассы задаётся только `control_points` в `assets/data/tracks/*.tres`
  (замкнутый сплайн Catmull-Rom, `scripts/track_builder.gd`), код трогать не нужно.
- Прямые участки: серии коллинеарных контрольных точек (сегмент сплайна прям,
  когда 4 соседние точки коллинеарны). Углы — 2–3 точки, без резких изломов.
- Несмежные участки трассы держать врозь: `tools/gen_track.gd` требует
  межосевой зазор ≥ 40 м, радиус поворота ≥ 22 м, длину круга 1000–2400 м и
  ≥ 3 прямых под буст-пады (пороги откалиброваны по существующим трассам).
- Фолбэк-дефолт в `scripts/track_def.gd` синхронизировать с `city_01.tres`.

Генерация/подбор трасс (сидированный контур + валидация + контактный лист):

```
/media/alexander/data/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tools/gen_track.gd -- mode=sheet biome=coast count=16 seed=7000
/media/alexander/data/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tools/gen_track.gd -- mode=emit biome=coast seed=7013 id=coast_02 display="Coast II"
```

Контактный лист и метрики кандидатов — в `/tmp/opencode/track_sheet_<biome>.{png,txt}`.
Для нового биома без своего `<biome>_01.tres` шаблон декора берётся через `template=<id>`.
Регистрация новой трассы — в `TRACK_IDS` (`scripts/game_state.gd`).
