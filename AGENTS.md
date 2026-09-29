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
