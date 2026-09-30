# SimpleRacing — манифест ассетов

Версия: 0.1 · Дата: 2026-09-24
Стиль: смешанный (реалистичные PBR-текстуры + аркадная подача).
Таргет: мобильные (Android в первую очередь). Источник: AI-генерация + ручная доводка.

## 1. Общие правила

- Имена: `snake_case`, латиница; id сущностей (`car_id`, `biome_id`) — короткие (`sport_01`, `city`).
- Текстуры: WebP (альбедо/эмиссия) и PNG (normal/ORM — без потерь), power-of-two, мипмапы on.
- Запрещено: альбедо с запечённым освещением (только плоский цвет/грязь), не-POT текстуры, стерео для 3D-звука.
- Провенанс: рядом с ассетом `*.license` (инструмент, дата, промпт, права). Без записи ассет не принимается.
- Единый style-guide: тёплая палитра, насыщенные акценты, чистые PBR-значения (roughness без «мыла»).

## 2. Бюджеты (мобильные)

| Тип | Лимит |
|---|---|
| Альбедо/ливрея авто | 1024² |
| Normal/ORM авто | 1024² (ORM можно 512²) |
| Тайлы дороги/террейна | 1024² |
| Пропсы (текстуры) | 512² |
| HDRI | 2048×1024 |
| Меши: герой-авто | LOD0 ≤ 15k, LOD1 ≤ 5k, LOD2 ≤ 1.5k трис |
| Колесо | ≤ 1.5k трис |
| Пропс | ≤ 2k трис |
| Аудио SFX (позиционное) | OGG, моно, ≤ 2 с |
| Лупы двигателя | OGG, моно, 2–8 с, бесшовные |
| Музыка | OGG, стерео, 60–120 с луп |
| Бюджет ассетов в сборке | ≤ 120 МБ |

## 3. Транспорт: мотоциклы (игрок + AI) и трафик-автомобили

Гоночные мотоциклы — **реальные GLB-модели** со **Sketchfab, CC-BY 4.0**
(`assets/bikes/<id>/body.glb` + внешние текстуры + `.license`). Сверху
монтируется **процедурный райдер** (`scripts/rider.gd`) — он сохраняет
перекраску по цвету соперника и рабочие позы удара/пинка/кувырка; посадка
задаётся `BikeDef.rider_mount`/`rider_scale`. Ростер: `scrambler_01`,
`sport_01`, `cruiser_01`, `super_01` + `cop_01` (`assets/data/bikes/*.tres`).

| id | модель | автор | трис |
|---|---|---|---|
| scrambler_01 | DIRT BIKE OFF ROAD BIKE LOW POLY | nabeelashrafphotography | ~17k |
| sport_01 | Honda CB 750 F Super Sport 1970 | Alex.Ka. | ~37k |
| cruiser_01 | Motorcycle Fallout | milinam2002 | ~20k |
| super_01 | HCR2 Superbike | oakar258 | ~30k |
| cop_01 | Low Poly Motorcycle 001 | roh3d | ~5.5k |

`BikeDef.model_path` включает GLB-ветку (иначе — процедурный фолбэк
`scripts/bike_visuals.gd`, если модель недоступна). Наклон в поворот и вилли
на нитро применяются к узлу `Tilt` (bike-space), поэтому работают и для GLB
независимо от `model_yaw`.

Колёса: `race_bike.gd._collect_wheels` собирает ноды с `wheel` в имени (кроме
`steer`/`handle`) — у модели super_01 (HCR2) есть `wheel_front`/`wheel_rear`,
они крутятся и переднее рулится. У моделей с запечёнными колёсами (`dirt`,
`honda`, `fallout`, `roh3d`) нод нет — колёса статичны (спин невидим, но
байк стоит на земле). `_update_wheels` ставит
`vehicle_global * tilt * T(hub_rel) * R(up, steer) * R(right, spin)`.

Пайплайн мотоциклов: `sf_search.py`/`sf_download.py` (токен в
`/tmp/opencode/sketchfab_token`, в репо не хранится) → `process_bike.py`
(gltf-transform dedupe+resize ≤1024² → `normalize_bike.py`: земля y=0, центр по
bounds, переименование колёс в `wheel_front`/`wheel_rear`, PBR-фиксы, масштаб
до длины байка) → `externalize_textures.py` (текстуры наружу). Ориентация
подбирается `model_yaw` из отчёта `normalize_bike.py` (forward=…). Проверка:
`tools/bike_close_shot.gd` (BIKE=0..3, NODE=Police, POSE=punch|kick|crash).

### Трафик (5 автомобилей)

Источник: **Sketchfab, CC-BY 4.0**. Атрибуция — экран CREDITS в меню +
`body.glb.license`. Модели лежат в `assets/cars/traffic_*/body.glb`, def-ы — в
`assets/data/traffic/traffic_*.tres` (класс `BikeDef`, используется `model_path`
и габариты; спавн — `scripts/traffic.gd`).

| id | модель | автор |
|---|---|---|
| traffic_sedan | BMW E46 1998 | roh3d |
| traffic_van | Shvan '92 (VW T4) | DanielZhabotinsk |
| traffic_taxi | Illinois '90 Taxi | DanielZhabotinsk |
| traffic_wagon1 | BMW E30 1985 | roh3d |
| traffic_wagon2 | Fairheaven SW '84 | DanielZhabotinsk |

Пайплайн GLB-моделей (трафик/будущие): `sf_search.py`/`sf_download.py` (токен в
`/tmp/opencode/sketchfab_token`, в репо не хранится) → `process_car.py`
(gltf-transform dedupe+resize ≤512²) → `normalize_car.py` (земля y=0, пивот в
центре колёсной базы, угловые колёса `_fl/_fr/_rl/_rr`) →
`externalize_textures.py` (текстуры наружу файлами). Ориентация: серии
DanielZhabotinsk/Ferrari — вперёд +X (`model_yaw = PI/2`), roh3d — +Z
(`model_yaw = PI`). Проверка колёс: `tools/wheel_check.gd`
(GLB/SPIN/STEER/YAW/NOBODY env) и `tools/bike_close_shot.gd` (крупный план в
игре).

## 4. Окружение (биомы: city, desert, alpine, coast)

`assets/environments/<biome>/`
- `road/`: `asphalt_albedo.webp`, `asphalt_normal.png`, `asphalt_orm.png`, атлас разметки (полосы, стрелки, зебра).
- `terrain/`: grass/dirt/gravel/sand/rock — albedo+normal+ORM, тайл 4–8 м.
- `props/`: деревья ×3, кусты ×2, камни ×3, по биому (кактусы/пальмы/ели), здания (модульный кит: стена/угол/крыша), трибуна, пит-билдинг, стартовая арка, вышка, баннеры ×4, щиты ×3, фонарь, тоннель-секция, мост.
- `impostors/`: дальняя гряда/скайлайн — билборд 1024×512.
- `sky.hdr` + `sky_params.tres`.

Промпты (тайлы): `seamless tileable [asphalt/grass/dirt] PBR albedo texture, top-down, even lighting, no shadows, high detail, photorealistic`.
Промпты (скай): `360 equirectangular panorama HDRI sky, [clear sunset / noon], 2:1 aspect ratio`.

## 5. UI

- Шрифты (OFL, с кириллицей): `ChakraPetch` (display) + `Inter` (UI) → `assets/ui/fonts/`.
- Иконки (SVG→PNG 128², монохром + акцент): nitro, flag, lap, timer, trophy, settings, pause, back, lock, garage, track.
- HUD: спидометр (циферблат+стрелка), шкала нитро, рамка миникарты; панель круга/времени/позиции; отсчёт 3-2-1-GO.
- Меню: логотип, фон (AI-концепт → чистка), кнопки (normal/hover/pressed), панели, карточки машин/трасс, слайдеры, экраны паузы/результатов/лидерборда.
- Тач-контролы: руль/кнопки газ-тормоз-нитро (PNG 256², 9-patch где нужно).

Промпт (фон меню): `arcade racing game menu background, [biome] track at sunset, stylized photorealistic, dramatic lighting, no text, no UI, wide composition`.

## 6. Аудио

`assets/audio/`
- `engine/<car_class>/`: `idle.ogg`, `on_load_{low,mid,high}.ogg`, `off_load_{mid,high}.ogg`, `shift.ogg`, `turbo.ogg`, `blowoff.ogg`, `backfire.ogg`.
- `tires/`: `roll_{asphalt,gravel,grass}.ogg`, `screech.ogg`, `skid.ogg`.
- `impacts/`: `hit_light/heavy.ogg`, `scrape.ogg`, `landing.ogg`.
- `ui/`: click, hover, back, error, countdown_{1,2,3,go}, lap, best_lap, finish, unlock.
- `ambience/<biome>/`: wind, crowd, birds.
- `music/`: menu, race_{city,desert}, results.

Лупы двигателя: генерить длинный дубль → резать на кроссфейде по нулю фазы; проверка на щелчки обязательна.
Промпт (музыка): `energetic arcade racing loop, 128 BPM, synthesizers, driving beat, no vocals, seamless loop`.

## 7. VFX

`assets/vfx/`: `puff_soft.webp`, `spark.webp`, `streak.webp`, `flame.webp`, `glow.webp`, `confetti.webp`, `skidmark.webp`, `dirt_splash.webp` (256², альфа).
Промпт: `particle sprite, soft round smoke puff, white on black background, single, centered` (и вариации для искры/пламени).

## 8. Данные и интеграция

- `TrackDef` (tres): контрольные точки сплайна, ширина, биом, точки рамп/пропсов. Вынесен из `track_builder.gd`; лежит в `assets/data/tracks/` (city_01, desert_01).
- `BikeDef` (tres): силуэт/палитра процедурного байка, габариты, статы, класс звука двигателя (и опциональный `model_path` GLB). Лежит в `assets/data/bikes/` (scrambler_01/sport_01/cruiser_01/super_01). Трафик — в `assets/data/traffic/`.
- `race_bike.gd` читает BikeDef; строит байк через `bike_visuals.gd` (+ `rider.gd`), колёса (`wheel_front`/`wheel_rear`) крутятся, переднее — рулится, есть визуальный крен в поворот; `driver: AiDriver` переключает ввод на AI.
- AI-соперники: `AiDriver` (следование по центральной линии, торможение по кривизне, нитро на прямых, anti-stuck) + `RacerProgress` для живых позиций (HUD «POS x/4»).
- Аудио-шины: `Master/Music/SFX/Engine` (`default_bus_layout.tres`); автолоад `Audio` проигрывает только существующие файлы (no-op, пока ассетов нет). Музыка: menu, race_city, race_desert (процедурные лупы).
- HUD: шрифт ChakraPetch; меню (`scenes/menu.tscn`) — выбор мотоцикла/трассы, автолоад `Game` передаёт выбор в гонку.
- Тач-контролы: `TouchControls` (мультитач-кнопки → Input actions; F4 — переключить на десктопе).
- Инструменты: `tools/preview_shot.gd` (скриншоты через xvfb; SHOT=menu|race, TRACK, WAIT_MS), `tools/ai_probe.gd` (диагностика AI: TRACK, SOLO=n, TIME_SCALE), `tools/bike_close_shot.gd` (крупный план байка).
- AI-надёжность: соперники-призраки (не сталкиваются друг с другом), watchdog-респавн при заторе >2.5 с, wall-bias (руль от стены по боковому смещению), wrong-way разворот, личные коридоры ±1.6 м; рампы не ближе 60 сэмплов от старта.
- Текстуры земли/дорог: photoreal альбедо через SwarmUI (**Z-Image Turbo**, `gen_sdxl_tex.py`, хост `127.0.0.1:7801`): генерация 1536² → detrend (снятие запечённых градиентов) → бесшовность «offset+heal» (wrap-blend краевой полосы с интерьером; FFT-метод с фейдом больше не используется — давал полосы и тёмную кайму) → даунсемпл 1024² + unsharp. Best-of-3 сидов на материал (скор: микродеталь минус шаг шва). Normal считается из 1536²-люминантности, ORM — из финального альбедо. Светлые дороги (desert/coast/canyon/sakura) после генерации тонироваются множителем до целевой яркости (контраст с песком; заметка в `.license`). Процедурные версии лежат в `tools/fallback_textures/` как fallback. Godot importer defaults включают VRAM compression и mipmaps; normal-флаг проставляет `tools/assetgen/patch_imports.py`.
- Фасады зданий: **все биомы — `facade_{a,b,c,d}.webp` + normal/ORM** (`gen_sdxl_tex.py`, аргумент `<biome>_facades`; движение `_make_facade_materials` читает a–d и молча пропускает отсутствующие). Emission-маски окон (night) — только city (`city_emission`, перегенерировать после замены городских альбедо); ночные альбедо `facade_*_night.webp` выводятся процедурно: `день*0.14 + эмиссия*0.95` (гарантирует совпадение окон); применяются локальным трипланаром (тайл 3 м), на трибунах — тайл 1.5 м; fallback — плоские цвета.
- Пропсы-билборды: city — 6 деревьев и 2 куста (`props/*.png`, `gen_props.py`); другие биомы — по 3 хромакей-спрайта. Y-билборды Sprite3D ставятся по нижней границе контента, с contact-shadow; fallback — примитивы.
- Декор: параметры `TrackDef.decor_*`; растения и здания выбираются вдоль сплайна трассы, а не случайным кольцом. Здания — процедурные объёмы (block/slab/podium/stepped) с парапетами, крышами и rooftop-деталями.
- Городские здания (city, `urban_canyon`): **BuildingKit** из реальных мешей —
  **Sketchfab CC-BY 4.0** + **NeonTown (CC0, OpenGameArt)**:
  `assets/environments/city/buildings/` — bank/bar/pharmacy/restaurant/store
  (NeonTown), aptcomplex/brooklyn/chicago/citybld/oldapt/rohbld/urbanhouse/
  largebld (Sketchfab: jimbogies, B0rn2D13, 99.Miles, mireubay1, AspectStudio,
  roh3d). Нормализация `normalize_building.py` (земля y=0, пивот пятна,
  кламп footprint ≤22 м, диорамы дорастают до ~14 м высоты), текстуры ≤1024²
  (512 у пропсов) и вынесены наружу (`externalize_textures.py`).
  `track_builder.gd`: ближний пояс — `_make_kit_building` (поворот по
  tangent_yaw, масштаб ×0.9–1.25, камерный блокер по честному AABB с
  накоплением трансформов предков, неон-вывеска ночью), дальний пояс —
  `_make_kit_skyline` (городские башни citybld/largebld, масштаб с кэпом
  полудиагонали 40 м и валидацией по фактическому размаху; конвенция
  `skyline_transforms` сохранена для `tools/check_buildings.gd`). Днём
  эмиссия окон гасится (`_tune_kit_materials`), ночью — ×1.5. Фолбэк при
  отсутствии кита — процедурные объёмы (следующий пункт).
- Бардюры/городской пейзаж вдоль трассы (все биомы): старый процедурный
  «забор» (красно-белая стена, `_make_wall`) заменён на бордюрный камень
  **Kenney "City Kit (Roads)" (CC0)** — `assets/environments/city/curbs/`,
  односторонний профиль бардюра вырезан из `road-straight-barrier.glb`
  (`normalize_curb.py`: земля y=0, внутреннее ребро в x=0, 0.18×0.18×1 м).
  `track_builder.gd`: `_make_curbs` укладывает сегменты вдоль централайна
  одним MultiMesh на сторону (шаг 0.8 м, у MultiMesh масштаб игнорируется —
  поэтому укладка по дуге, а не растяжка; фолбэк — цветной рибон-бордюр);
  `_make_barrier` — невидимая коллизия-стена (машины не покидают трассу,
  AI wall-bias/звук удара сохранены). Низкая фасадная лента
  `_make_facade_band` (биомные `facade_*`, трипланар 4.5 м, цоколь, разброс
  высоты и выноса), закрывавшая барьер на открытых биомах, удалена: сплошная
  стена с фасадной текстурой читалась как мозаичный забор и превращала
  desert/coast/alpine в «трубу», поэтому на них теперь остаётся только бордюр
  и невидимая коллизия. В городе (`urban_canyon`) —
  `_make_street_front`: **плотный первый ряд** реальных kit-зданий вплотную
  за тротуаром (отступ 1.2–3.2 м, зазоры 1–4 м, изредка «переулок»),
  ориентация по `tangent_yaw`, футпринт из честного AABB; каждый седьмой дом
  подменяется башней (`citybld`/`largebld`) с пересчётом масштаба под ту же
  длину по трассе, половина домов развёрнута на 180° — улица читается как
  городской каньон, а не как забор. Кандидаты, задевающие другую секцию
  трассы (по конвенции `tools/check_buildings.gd`), отбрасываются с
  небольшим шагом; первый ряд гаснет дальше 320 м (`visibility_range`),
  горизонт закрывает существующий skyline.
- SwarmUI: нода SwarmModelTiling роняет ComfyUI-бэкенд на этой установке — не использовать `seamlesstileable`. Инстанс слушает `127.0.0.1:7801` (порт меняется пользователем — проверять `GetNewSession` перед генерацией). Не грузить вторую модель (SDXL) при резидентной — OOM 12 ГБ клинит сессии SwarmUI (лечится перезапуском UI). Z-Image Turbo: CFG 1 — негатив-промпты игнорируются, весь контроль через позитив.
- Модельный пайплайн (открытые ассеты): `tools/asset_preview.gd` (рендер
  превью пака GLB в Godot: DIR/OUT env), FBX2glTF 0.9.7 (FBX→GLB),
  `tools/assetgen/normalize_car.py` / `normalize_building.py` (pygltflib:
  нормализация pivot/масштаба/PBR). poly.pizza и itch.io без аккаунта не
  отдаются (API/CSRF) — рабочие источники: OpenGameArt (прямые файлы),
  kenney.nl, quaternius.com.

## 9. Порядок работ

- **P0 (ядро) — ГОТОВО:** PBR-набор машины (ливреи+normal+ORM), асфальт/трава/песок/снег, sky.hdr ×4, звук двигателя/шин/UI/impacts/музыка ×3, шрифты, арт HUD.
- **P1 — ГОТОВО:** 4 машины (классы + ливреи), AI-соперники + позиции, биом desert, меню+музыка, тач-контролы.
- **P2 — ГОТОВО:** биомы alpine+coast, прогрессия (save.cfg, разблокировки: sport после финиша, muscle за подиум, hyper за победу), VFX (дым шин, пыль, искры, конфетти), adaptive icon + feature graphic.
- **P3 — ГОТОВО (2026-09-28):** машины и городские здания переведены на
  реальные mid-poly PBR-модели со Sketchfab (CC-BY 4.0, авторы — см. экран
  CREDITS в меню и `*.license`): 4 героя + 5 трафик-Def-ов, 13 вариантов
  зданий + skyline-башни. Пайплайн: sf_search/sf_download → gltf-transform →
  normalize_car/normalize_building → externalize_textures. Старый AI-меш
  `assets/car.glb`, ливреи старой модели и RGSDEV-машины удалены (RGSDEV-пак
  остаётся запасным источником трафика). Сырые ассеты ~150 МБ; в сборке
  меньше за счёт VRAM-компрессии — при превышении бюджета жать текстуры
  трафика/зданий до 512².
- **P4 (Road Rash) — M1–M3 ГОТОВО (2026-09-30):** гоночные автомобили заменены
  на **процедурные мотоциклы с сидящими райдерами** (`bike_visuals.gd`,
  `rider.gd`); код и данные переименованы car→bike (`RaceBike`, `BikeDef`,
  `BikeTuning`, `assets/data/bikes/`). Геройские GLB удалены, 5 трафик-машин
  сохранены (def-ы в `assets/data/traffic/`). Сейв мигрируется (старый
  `car_index`/апгрейды `compact_01…` читаются как bike-эквиваленты). Добавлены
  механики Road Rash: **бой** (Q/E удар, F пинок, здоровье, нокдаун→вайпаут→
  ремаунт, AI-агрессия; `scripts/race_bike.gd`), **полиция** (`scripts/police.gd`:
  погоня, BUSTED, бонус за сбитого копа) и **трафик** (`scripts/traffic.gd`:
  5 GLB-машин по полосам, краш). Проверка боя — `tools/check_combat.gd`.
- **P5 (2026-09-30):** процедурные байки заменены на **реальные GLB-модели со
  Sketchfab (CC-BY 4.0)**: 4 класса + коп (`assets/bikes/<id>/body.glb`). Райдер остался
  процедурным (сохраняет позы боя/вайпаута) и монтируется по
  `BikeDef.rider_mount`. Пайплайн — `tools/assetgen/process_bike.py`
  (+ `normalize_bike.py`); у HCR2-супербайка есть отдельные колёса (спин/руль),
  у остальных колёса запечены. Наклон/вилли вынесены в узел `Tilt` (bike-space),
  так что работают для GLB с любым `model_yaw`.

## 10. Критерии приёмки

- Ассет проходит бюджет (раздел 2) и есть `.license`.
- Тайл проверен в Godot на бесшовность при тайлинге 4×4.
- Луп — без щелчков на стыке (проверка в аудио-редакторе).
- Меши: LOD-переключение не «прыгает» с камеры погони.
- Итоговая сборка ≤ 120 МБ.
