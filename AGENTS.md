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

## Графика / стиль

- Аркадный cel-стиль актёров (райдер, байки, трафик): `assets/shaders/toon.gdshader`
  (3-тоновый half-lambert + rim) + `assets/shaders/toon_outline.gdshader`
  (inverse-hull обводка как `next_pass`); фабрика — `scripts/toon_material.gd`
  (цвета/liveries остаются данными). Трафик — без обводки (8 машин).
- Текстуры мира — тот же flat-cel стиль: дороги процедурные
  (`tools/assetgen/gen_road.py`, все биомы, tint+акценты), террейны/фасады —
  `tools/assetgen/gen_sdxl_tex.py` (Z-Image Turbo; стиль идёт в НАЧАЛО промпта —
  модель обрезает хвост; негативы игнорируются при CFG 1.0). Пропсы-биллборды —
  `tools/assetgen/gen_props.py` (Qwen-Image, хромакей). Дома building-kit GLB
  cel-ятся в рантайме (`track_builder._tune_kit_materials` → `ToonMaterial`).
- Резкость: `project.godot` — MSAA 4x, anisotropic 16, `texture_mipmap_bias=-0.35`.
- Качество картинки (`scripts/graphics_quality.gd`): пресеты LOW/MEDIUM/HIGH
  (3D render scale, MSAA, тени, ночной Forward+ пост-стек) + AUTO в меню
  (строка QUALITY; мобилки → LOW, десктоп → HIGH). Выбор в `Game.quality`
  (`QUALITY_IDS`, сейв `graphics/quality`), viewport применяет `Game._ready`,
  env/солнце — `main.gd _build_environment`. Проверка — `tools/check_quality.gd`.
- Свет/грейдинг — `main.gd _build_environment()`: солнце 4-сплит PSSM, резкие
  тени; день — LINEAR-тонмаппинг, насыщенность 1.22, лёгкий туман; ночь (если
  включена) — ACES чуть светлее. Небо — тонкая тёплая полоса у горизонта и
  насыщенный купол (`gen_sky.py render()`); генераторы: `gen_sky.py`
  (city/canyon/sakura/volcano), `gen_biomes.py --sky` (alpine/coast),
  `gen_desert.py --sky` (desert) — флаг `--sky` не трогает террейны/дороги.
  `CITY_NIGHT` зарезервирован под будущие ночные city-трассы.
- Фонари (`track_builder._make_street_lights`): toon-столб/голова с обводкой,
  тёплая светящаяся линза (днём тоже) и аддитивное хало-биллборд; ночью —
  OmniLight + светопул. Скриншот — `tools/streetlight_shot.gd` (xvfb-run).

## Мотоциклы (Road Rash)

- Гоночный транспорт — **реальные GLB-модели** (Sketchfab CC-BY) в
  `assets/bikes/<id>/body.glb` + процедурный райдер на **Skeleton3D**:
  `scripts/bike_visuals.gd` (рама/колёса — фолбэк), `scripts/rider.gd`
  (кости строятся кодом, меши через `BoneAttachment3D`; посадка и позы —
  2-костный IK), данные — `BikeDef` в `assets/data/bikes/*.tres`
  (`model_path`, `model_yaw`, `rider_mount`). Пайплайн моделей —
  `tools/assetgen/process_bike.py` (+ `normalize_bike.py`).
- Райдер: посадка по `BikeDef.style` (sport/super — наклон вперёд, cruiser —
  отвесно), руки тянутся IK к рулю, ноги — к подножкам. Точки задаются
  `BikeDef.handlebar_local`/`peg_local` (bike-local; `Vector3.ZERO` = дефолт
  стиля из `RIDER_STYLES`). Рантайм-динамика (`set_drive`): наклон головы в
  поворот, вибрация от скорости, тюк на нитро; удары — 3-фазные (замах →
  выпад), крэш — кувырок с разлётом. Скриншоты поз — `tools/rider_shot.gd`
  (`xvfb-run`, env `BIKE`, `POSE=idle|punch|kick|crash`, `AZ`, `ELEV`, `DIST`);
  headless-проверка рига/IK — `tools/check_rider.gd` (PASS).
- Ростер: `scrambler_01`, `sport_01`, `cruiser_01`, `super_01`, `dirt_01`,
  `chopper_01`, `electric_01`, коп `cop_01`, байки боссов `boss_atlas`,
  `boss_kitsune`, `boss_cinder`. Первые три босс-байка — покупка в гараже
  (`Game.SHOP_BIKES`, кредиты; `owned_bikes` в сейве), остальные — за прогресс
  лестницы.
  Наклон/вилли — узел `Tilt` (bike-space), `BikeDef.lean_max`. Колёса
  крутятся, если у GLB есть ноды `wheel`/`tyre` (иначе статичны).
- Скины райдера (`scripts/rider_skin_def.gd`, `assets/data/skins/*.tres`):
  глобальный скин игрока (не пер-байковый), выбирается в гараже (панель RIDER
  SKIN, Tab — переключение панели). Цвета (suit/accent/helmet/glove/boot/visor)
  с alpha 0 наследуются от `BikeDef`; каталог `Game.SKIN_IDS`, цены
  `Game.SHOP_SKINS`, сейв — `selected_skin`/`owned_skins`. Скины `rose`/`gold`
  открываются за боссов (`unlock_boss`); у `stock` тоже есть эмблема (щит),
  цвет берётся из акцента байка. Декали-эмблемы (грудь + бока шлема) —
  RGBA-текстуры `assets/skins/<id>/decal.png` (белый RGB + узор в альфе),
  тонируются `accent_color` (alpha-scissor материал). Генерация —
  `tools/assetgen/gen_rider_skins.py` через SwarmUI (Z-Image Turbo), проверка —
  `tools/check_skins.gd`. Игроку скин ставит `main.gd` (`RaceBike.player_skin`),
  AI/боссы — цвета `BikeDef` (у боссов свои именные цвета).
- Бой (Road Rash): Q/E — удар влево/вправо, F — пинок; здоровье в HUD,
  нокдаун → вайпаут → возврат через 4.2 с. Вайпаут — фазовый цикл райдера
  (`rider.gd`: eject → getup → run → lift → mount): райдер вылетает с байка,
  встаёт, бежит к нему, поднимает и садится. На вайпауте `Rider` временно
  перепарентен из `Tilt` в `RaceBike` (тело физики вертикально), `_tilt`
  валится/встаёт синхронно с фазой (`rider.is_remounting()`). Скриншоты фаз —
  `tools/bike_close_shot.gd` (`POSE=eject|getup|run|lift|mount`).
  Логика в `scripts/race_bike.gd` (+ `rider.gd`), AI-агрессия — `AiDriver.decide_attack`.
- Урон: удары, а также столкновения (в машину — 10–40 по скорости, в стену —
  6–25; impact считается по **относительной** скорости ДО `move_and_slide`).
  Байк-в-байк (соперник/коп) урона не наносит: `_apply_bump` толкает жертву
  (wobble + сдвиг), вайпаут только от ударов. Трафик (`is_traffic`) и стены —
  жёсткие. Быстрые байки едут почти вровень, поэтому абсолютная скорость давала
  ложный «импакт» 26+ → мгновенный вайпаут при догоне (`_resolve_impact`).
  ИИ-соперничество: резинка ±10% (`main.gd`), обгон на скорости
  (`AiDriver._blocker_much_slower`), мщение атакующему 4 с (`grudge`).
- Полиция (`scripts/police.gd`): коп появляется с задержкой (`POLICE_DELAY` env
  для теста) и преследует игрока; при скорости <6 м/с рядом с копом 2.5 с —
  BUSTED. Сбитый коп даёт бонус. Трафик (`scripts/traffic.gd`): 8 GLB-машин из
  `assets/data/traffic/` едут по полосам (обычные + `traffic_moto` быстрый и
  виляет, `traffic_sport` быстрый, `traffic_bus` широкий медленный; повадки —
  `TrafficDef.speed_mult`/`weave_amp`/`nm_width`); быстрый удар = вайпаут.
  У каждой машины `model_yaw` в `assets/data/traffic/*.tres` должен разворачивать
  нос модели в −Z (иначе машина «едет боком»): проверка
  `tools/check_traffic_orient.gd` (PASS/FAIL), рендер-контроль —
  `tools/car_orient_shot.gd` (через `xvfb-run`, `CAR_ID=<id>` для одной модели).
- Пикапы/опасности (`scripts/track_pickup.gd` и наследники; спавн —
  `track_builder.gd`, детерминированно по `decor_seed`): нитро, аптечка,
  деньги (`CashPickup` — только игрок, +кредиты), щит (`ShieldPickup` — 8 с
  иммунитета к ударам), масло (`OilSlick` — грип ×0.32 на 3.5 с), конус
  (`TrafficCone` — 5 урона на скорости >6 м/с). HUD: индикатор `SHIELD`.
- Боссы (`scripts/bosses.gd`): на `canyon_01`/`sakura_01`/`volcano_01` быстрый
  слот соперника заменяется именным боссом (skill 1.0, высокая агрессия, без
  резинки). Первая победа даёт разовый бонус кредитов (`Game.beat_boss`).
  Байки боссов (`boss_atlas`/`boss_kitsune`/`boss_cinder`) покупаются в гараже
  за кредиты (`Game.SHOP_BIKES`, `Game.buy_bike`, `owned_bikes` в сейве).
- Проверки баланса/магазина/кампании/боя/механик (должны быть PASS):
  `tools/check_tuning.gd`, `tools/check_shop.gd`, `tools/check_campaign.gd`,
  `tools/check_combat.gd`, `tools/check_mechanics.gd`, `tools/check_rider.gd`,
  `tools/check_skins.gd`, `tools/check_traffic_orient.gd`, `tools/check_buildings.gd`,
  `tools/check_touch.gd`, `tools/check_quality.gd`.
- Скриншот байка крупным планом: `tools/bike_close_shot.gd` (через `xvfb-run`;
  POSE=punch|kick|crash для боевых поз). Превью трасс/гаража — `tools/gen_track.gd`,
  `tools/preview_shot.gd` (`SHOT=menu|race|garage`).

## Мобильное управление

- `scripts/touch_controls.gd` (`TouchControls`, CanvasLayer): пад рисуется кодом,
  показывается при `DisplayServer.is_touchscreen_available()` (F4 — тумблер на
  десктопе, `FORCE_TOUCH=1` — для скриншотов). Кнопки — PNG-иконки
  (`assets/ui/touch/*.png`, генератор `tools/assetgen/gen_touch_icons.py`,
  белые силуэты + tint): педали газа/тормоза — силуэты педалей, нитро — пламя,
  удары — кулак/ботинок. Раскладка в относительных единицах (доля высоты
  вьюпорта), единый `_layout()` для визуала и хит-тестов.
- Схема: слева внизу — аналоговая зона руления (drag, сила = позиция X,
  инжект `Input.action_press("steer_left/right", strength)` → `Input.get_axis`
  в `race_bike.gd`), над зоной в ряд удары; справа внизу — педали газа
  (крупная) и тормоза, а **нитро — прямо над педалью газа** (правый большой
  палец рулит газом и давит нитро вторым пальцем, не бросая газ). Зажатое
  нитро само даёт тягу (`RaceBike._player_input`: nitro ⇒ throttle, тормоз
  сильнее), так что одного пальца на нитро достаточно. Мульти-тач: газ+нитро
  держатся одновременно (у каждого пальца свой `index → action`).
- HUD на мобильном (`Hud.set_mobile`): блок скорости/здоровья/нитро — по центру
  внизу, клавиатурная подсказка скрыта; bottom-углы отданы паду.
- Проверка раскладки/мульти-тача/аналога — `tools/check_touch.gd` (PASS).

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
