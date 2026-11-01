# DGX Sparkでの構築・検証の記録

DGX Spark（aarch64、GB10）でLabUtopia（NeurIPS 2025）を動かしたときの作業記録です。手順の要約は[README](../README.md)にあります。文中の `out/...` は実行時の出力先で、リポジトリには含めていません。

| 項目 | 構成 |
|---|---|
| ソース | `repo/`：[Rui-li023/LabUtopia](https://github.com/Rui-li023/LabUtopia) のコミット `8df72784265c375a327ffa3f0a0cf8c676f229a7`。LFSのアセット（約600MB）は取得済みで、欠落はない |
| Python | uv管理のCPython 3.11.17（`.python/`） |
| Isaac Sim | 5.1.0（`isaacsim[all,extscache]`、aarch64版） |
| PyTorch | 2.10.0+cu130、torchvision 0.25.0+cu130、torchaudio 2.10.0+cu130 |
| そのほか | `repo/requirements.txt` の版どおり（numpy 1.26.0 など） |

## uv環境

`pyproject.toml`・`uv.lock`・`.venv/`（17GB）は、このディレクトリ専用です。`isaacsim-core 5.1` はtorch 2.7.0（CUDA 12.8版）に固定されていますが、GB10ではCUDA 13版が必要です。CUDA 13版のaarch64パッケージは、torchvisionが0.25、torchaudioが2.10からしかないので、`override-dependencies` で上の版に上書きしています。上流のREADMEも、Isaac Simの固定を無視してtorch 2.9を入れる手順になっています。

```bash
bash scripts/uv.sh sync --frozen
```

## 実行

`scripts/run_main.sh` は、次の設定をしてから、`repo/main.py` を画面なしで実行します。

- ライセンス同意の記録（`environment/eula-consent.json`）を確認したうえで、`OMNI_KIT_ACCEPT_EULA=YES` を設定
- `LD_PRELOAD` で libgomp を事前に読み込む
- 静的TLSを拡張する（`GLIBC_TUNABLES`）
- キャッシュをプロジェクト内に置く

設定ファイルは `configs/` から読み、出力は `out/実行日時_設定名/` に保存します。

```bash
bash scripts/run_main.sh dgx_level1_pick
```

デモを大量に集めるときは、`scripts/collect_parallel.sh` でIsaac Simを複数起動します。引数には、プロセスごとの本数を並べます。各プロセスは `out/実行日時_設定名_p<番号>/` に出力します。乱数のシードは固定されていないので、プロセスごとに物体の配置が変わります。`configs/collect_*.yaml` の本数は、環境変数 `LABUTOPIA_MAX_EPISODES` で指定します（既定は100）。

```bash
bash scripts/collect_parallel.sh collect_level2_HeatLiquid 34 33 33 -- --backend gpu   # 液体の粒子があるシーン
bash scripts/collect_parallel.sh collect_level1_place 50 50
```

`configs/dgx_level1_pick.yaml` は、上流の `level1_pick.yaml` を元にしたものです。エピソード数を3にし、出力先を環境変数 `LABUTOPIA_RUN_DIR` で指定できるようにしています。

## aarch64・画面なし実行のための変更

- `repo/main.py`：`--headless` オプションを受け取るのに使われておらず、`headless: False` で固定されていました。オプションどおりに動くようにし、画面なしのときは `cv2.imshow` を呼ばないようにしました（`patches/headless-main.patch`。CRLFの改行コードは保持）。
- Isaac Simの拡張機能は、Kitが起動したあとにtorchを読み込みます。aarch64ではここで `libc10.so: cannot allocate memory in static TLS block` が起き、`ld.so` のアサーションで異常終了しました（終了コード127）。`GLIBC_TUNABLES=glibc.rtld.optional_static_tls=16384` を設定すると解消します。

## 動作確認（2026-10-24）

`level1_pick`（Frankaで三角フラスコを掴んで持ち上げる課題）を、付属のお手本（ステートマシン）で3エピソード実行しました。結果は**3/3成功、終了コード0、起動から終了まで約169秒**です。

出力は `out/20261024-191409_dgx_level1_pick/` にあります。

- `dataset/episode_000{0,1,2}.h5`：各エピソードは634〜714ステップ。中身は、`actions` (T,8)、`agent_pose` (T,8)、`camera_{1,2,3}_rgb` (T,3,256,256)、`language_instruction`
- `dataset/meta/episode.jsonl`
- `video/episode_{0,1,2}.mp4`：3台のカメラを横に並べた映像。`episode_0_frames.png` で、接近・把持・持ち上げを目視で確認した

### ほかのタスクの確認（各1エピソード）

論文の各レベルから代表的なタスクを選び、`configs/smoke_*.yaml`（上流の設定から、エピソード数を1にして出力先を差し替えたもの）で実行しました。出力は `out/20261024-20*_smoke_*` と `out/20261024-21*_smoke_*` にあります。

| 設定 | 結果 | 時間 |
|---|---|---|
| `level1_pour` | 成功。HDF5と動画あり | 54秒 |
| `level1_open_door` | 成功 | 58秒 |
| `level2_StirGlassrod` | 成功。ただし標準のCPU物理では、PhysXが「粒子はGPUでしか動かない」というエラーを出す。`--backend gpu` を付けるとエラーは消え、成功する | 約4分 |
| `level3_PourLiquid` | 成功 | 58秒 |
| `level4_CleanBeaker` | 成功（7段階） | 173秒 |
| `level4_DeviceOperation` | お手本は8回中3回、全段階を完了した。しかし `device_operate_controller.py` が `write_cached_data()` を呼ばないので、HDF5が保存されず、終わらないまま900秒で打ち切った（上流のバグ） | 打ち切り |
| `level5_Navigation` | 経路を走りきり、HDF5も作られた。しかし終了時の書き込みで `actions` の長さが揃わず、`OSError`（型変換）になって異常終了した（終了コード139）。`actions` が壊れている | 113秒 |
| `level5_Mobile_manipulation` | 成功（Ridgeback＋Franka） | 130秒 |

### 学習用デモの収集（2026-10-30〜31）

`scripts/collect_parallel.sh` で、2つのタスクを5プロセス並列で集めました。所要時間は約3.5時間です。100本すべてで、HDF5の各データの長さがそろっていること、NaNがないこと、画像の形状を確認しました。

| タスク | 出力 | 本数 | お手本の成功率 | 1本の長さ（ステップ） | 容量 |
|---|---|---|---|---|---|
| `level2_HeatLiquid`（`--backend gpu`） | `out/20261030-23305{4,9}_collect_level2_HeatLiquid_p{1,2}/`、`out/20261030-233049_collect_level2_HeatLiquid_p0/` | 100 | 100/101 | 996〜1284（平均1083） | 18GB |
| `level1_place` | `out/20261030-2331{09,14}_collect_level1_place_p{0,1}/` | 100 | 100/100 | 271〜325（平均300） | 4.6GB |

各HDF5の中身は、`actions` (T,8)、`agent_pose` (T,8)、`camera_{1,2,3}_rgb` (T,3,256,256) uint8、`language_instruction` です。

- `level2_HeatLiquid`：「掴む → 置く → 押す」の全段階を記録しています。
- `level1_place`：`controllers/place_controller.py` は、「置く」段階だけを記録します。動画には掴む段階も映っています。推論するときも、掴む段階は付属のお手本が行い、学習した方策は置く段階だけを担当します。

### 学習と評価（ACT、`level1_place`、DGX Spark）

学習と評価の流れは次のとおりです。

1. `scripts/make_dataset.py` で、収集したエピソードを `data/<タスク>/episode_data.hdf5` に1つにまとめる。HDF5の外部リンクで参照するのでコピーはしない。ほかのマシンに送るときは、`--copy` で実体を持つファイルを作る
2. `scripts/train.sh` で学習する
3. `scripts/export_policy.py` で、推論用の重みを書き出す
4. `scripts/run_main.sh` か `scripts/collect_parallel.sh` で、`configs/eval_*.yaml`（推論モード）を実行する

```bash
.venv/bin/python scripts/make_dataset.py data/level1_place out/20261030-23*_collect_level1_place_p*
bash scripts/train.sh dgx_train_act data/level1_place act_level1_place training.num_epochs=60 training.checkpoint_every=10 training.val_every=20
.venv/bin/python scripts/export_policy.py out/train/<run>/checkpoints/latest.ckpt out/train/<run>/checkpoints/policy_ema.ckpt
bash scripts/collect_parallel.sh eval_act_level1_place 25 25
```

上流のコードはそのままでは学習も推論も動かなかったので、次の対応をしました。

- **依存パッケージ**：ACTのコードが、使っていない `IPython` を読み込んで止まる。`uv add ipython` で追加した。
- **学習データの形式**：学習データの読み込みは、1つにまとめた `episode_data.hdf5` しか受け付けない（`*.h5` が並ぶ形式に対応する分岐の手前で、このファイルを開いてしまう）。`make_dataset.py` で対応した。
- **学習の設定**：上流の `train_act_image_workspace.yaml` には2つの不整合がある。上流のファイルは変えず、`configs/train/dgx_train_act.yaml` で上書きした。
  - 学習コードが読む `checkpoint.topk` と `checkpoint.save_last_snapshot` がない。
  - `policy.camera_names` が `camera_0/1` で、データのキー（`camera_1_rgb`、`camera_2_rgb`）と合わない。
  - 検証データの割合が0で、`val_loss` が出ないため、上位チェックポイントは `train_loss` で選ぶ。
- **推論用の重みの形式**：学習の保存形式（dillで保存した `state_dicts`）と、推論側が読む形式（`{'state_dict': ...}`、キーの先頭に `model.` を1つ付けたもの）が違う。`export_policy.py` で、EMAの重みをテンソルだけのファイルに書き出す。推論側は、PyTorchの `weights_only` の既定のまま読める。
- **推論時の切り替え**：`controllers/place_controller.py` の推論モードには、掴む段階から方策の段階へ移る処理がなく、掴んだ姿勢で止まる。収集モードと同じ判定（お手本の掴みが完了し、物体が10cm以上持ち上がった）で切り替えるようにした（`patches/place-infer-handover.patch`）。

学習の速度は1.30イテレーション/秒（バッチ128）で、GPUの使用率は約95%、CPUにはほぼ余裕があった。60エポックで約3時間かかった。`train_loss` は0.34から0.0106まで下がった。保存は10エポックごとにしたので、評価には50エポック目のEMAの重みを使う。3エピソードの試しの評価（`out/20261031-151144_eval_act_level1_place_try/`）は3/3で成功した。

50エピソードの本評価は、**50/50（100%）で成功**した。出力は `out/20261031-15132{7,2}_eval_act_level1_place_p{0,1}/` で、2プロセス並列で約23分かかった。論文の値は、ACTが73.3%、DPが80.0%である。

- **1本の長さ**：掴む段階を含めて11.5〜18.2秒（平均13.1秒）。
- **成功の判定**：上流の `place_controller.is_success()` で判定する。ビーカーの水平位置が目標から5cm以内で、高さが初期位置から5cm以内になった時点で成功となり、エピソードを打ち切る。グリッパーを開いたかどうかは見ていない。
- **評価の条件**：配置の範囲は、学習データと同じである（分布内の評価）。
- **目視の確認**：無作為に選んだ8本の最終フレーム（`results/level1_place_final_frames.jpg`）で、ビーカーが目標の台の上にあることを確かめた。

液体の粒子（`PhysxParticleSystem`）があるのは、`lab_003`（撹拌、振とう、加熱、押下）と `clock.usd` だけです。`lab_001` の注ぐタスクは粒子を持たず、容器の姿勢で成否を判定します。

USDの解析ライブラリ `pxr`（USD 0.26）で、全USDレイヤを解析しました。OmniGraphのノードやスクリプト属性はありませんでした。外部の参照は、NVIDIA公式のIsaacアセット（`omniverse-content-production.s3-us-west-2.amazonaws.com`、Sektion Cabinet）1件だけで、初回の実行時に外部通信が発生します。

## セキュリティ確認

確認は2026-10-24に、実行前の静的な検査として行いました。結果は [security-review.md](security-review.md) にまとめています。

### 学習と評価（ACT、`level2_HeatLiquid`、DGX Spark）

**学習**

- 設定：`bash scripts/train.sh dgx_train_act data/level2_HeatLiquid act_level2_HeatLiquid training.num_epochs=51 training.checkpoint_every=10 training.val_every=1000`
- 所要時間：1エポックが847イテレーションで、約11分。51エポックで約9.5時間（2026-10-31 17:35 〜 11-01 03:02）。
- 損失：`train_loss` は0.157から0.0062まで下がった。
- 評価に使った重み：50エポック目のEMAの重み。

**評価**

- 設定：`configs/eval_act_level2_HeatLiquid.yaml` を `--backend gpu` で実行した。
- 補正なしの試し（`out/20261101-030236_eval_act_level2_HeatLiquid_try/`）：**0/3**。3本とも上限の2500ステップで打ち切られた。動画では、ビーカーを挟めても持ち上げると滑り落ち、つかみ直しを繰り返していた。

**失敗の原因**

1. **上流の成功判定の不具合**：`placepress_controller.is_success()` が `self.current_phase == Phase.FINISHED`（比較）になっていて、エピソードが終わらず、`_last_success` も立たなかった。`patches/placepress-infer-success.patch` で直した。
2. **把持力が出ない**：デモの `actions` は「次の時刻の関節角」なので、把持中の指の値はビーカーの幅（約0.0274）になる。お手本は0.022まで閉じる指令を出しており、その差が握る力になっていた。方策は約0.0274を指令するので、力がかからない。

**対策と結果**

- 対策：`patches/infer-gripper-squeeze.patch` で、推論時に指の指令が0.035未満（閉じる側）なら0.006だけ深く閉じるようにした。設定の `infer.gripper_squeeze` で有効になる。
- 補正ありの試し（`out/20261101-031436_eval_act_level2_HeatLiquid_try2/`）：3/3。
- 本評価：**49/50（98%）**。出力は `out/20261101-0321{41,46,51}_eval_act_level2_HeatLiquid_p{0,1,2}/`。3プロセス並列で約1時間45分かかった。
- 1本の長さ：成功した49回で21.9〜28.4秒（平均23.8秒）。
- 唯一の失敗（`p1` の `episode_16`）：腕がビーカーに近づかないまま、上限の2500ステップに達した。

### 論文の記述に沿った判定での再評価（2026-11-01）

公開コードの推論時の判定は「位置の条件に入った瞬間に成功」であり、論文より緩い。上流の全ブランチ（`main`、`isaacsim5.1`、`isaacsim4.2`、`Dev`）を確認したが、推論時の判定はどれも同じだった。`Dev` にある60ステップの維持判定は、再生モードだけで使われている。

**判定に使った論文の記述**

- 4.2節：「目標状態の許容範囲内に、最終段階の完了後2秒間続けて満たされる」
- 付録C.1.2：「容器を20cmより高く持ち上げる」

**実装**

- `patches/paper-success-eval.patch`：`base_controller._paper_success` を追加した。`infer.success_hold_steps` が0より大きいときに有効になる。持ち上げ高さと傾きを毎ステップ計測し、エピソードごとに `paper_eval.jsonl` へ書き出す。
- 傾きは、剛体を持つ子プリム（`<物体>/mesh`）のローカルZ軸と、開始時のZ軸のなす角として測る。親のXformは物理で動かないので、最初の版では常に0°になっていた。そのため測る対象を子プリムに直した。
- 設定：`configs/eval_paper_act_level1_place.yaml`（120ステップ）、`configs/eval_paper_act_level2_HeatLiquid.yaml`（120ステップ、20cm、グリッパー補正あり）。

**結果**

- `level1_place`：**50/50**。出力は `out/20261101-0911{09,14}_eval_paper_act_level1_place_p{0,1}/`。
  - 持ち上げ（お手本の掴み）は15.0〜19.1cm。
  - 成功時の傾きは、中央値6.6°・最大22.6°（握ったまま）。
- `level2_HeatLiquid`：**46/50**。出力は `out/20261101-0910{49,59}_..._p{0,2}/` と `out/20261101-1102{56}_..._p0`、`out/20261101-110301_..._p1`。
  - 最初のp1は、起動5秒後にIsaac Sim内部で異常終了した（5プロセスの同時起動が原因とみられる）。その分の17本は、2プロセスで評価し直した。
  - 失敗のうち3回は、許容範囲に入ったものの、維持が65〜83ステップで途切れた。動画で確認すると、ボタンを押したあとにグリッパーがボタンの部品を引っかけて外していた。残る1回は、ビーカーに近づかなかった。
  - 許容範囲に入った49回の持ち上げ高さは、20.6〜24.4cmだった。
  - 成功時の傾きは、中央値2.3°・最大6.7°だった。

### 補足：力制御での把持（2026-11-01）

上流の `Dev` ブランチ（`robots/franka/franka.py` の `set_gripper_control_mode("force")`、`enable_gripper_force_servo`）にある力制御を参考に、推論時だけ指を一定の力で閉じるモードを足した。論文には制御方式の記述がないので、位置の補正（上の46/50）を本命とし、こちらは比較として扱う。

**実装**（`patches/infer-gripper-squeeze.patch` の `infer.gripper_force`）

- 方策の指の値が `gripper_open_threshold`（0.035）未満なら、目標を全閉（0）にし、指の駆動の上限を `gripper_force`（N）にする。
- Isaac Sim 5.1 の Franka は、指の関節が2つ（DOF 7、8）あり、8は追従するだけの関節（ゲイン0）。7の標準の駆動は、位置ゲイン400・減衰80・最大7.2N。このままだと、全閉を指令しても力は 400×0.027 ≈ 11N にしかならず、20Nや40Nの上限が効かない。そこで、7だけ `Dev` ブランチの位置サーボと同じゲイン（6000、200）にした。
- 最初の試走は、このゲインの変更を入れる前の版で始めてしまったので、途中で止めた（出力は `out/_aborted/`）。

**結果**

- 試走（各3回、`out/20261101-1612{15,23,31}_..._force_try_f{10,20,40}/`）：すべて3/3成功。成功時の傾きは、10Nで1.8〜2.3°、20Nで9.0〜12.1°、40Nで19.6〜29.2°。強く握るほど傾く。
- 10Nでの評価（50回、`out/20261101-1637{11,16,21}_eval_paper_act_level2_HeatLiquid_force_p{0,1,2}/`、`LABUTOPIA_GRIPPER_FORCE=10`）：**50/50**（上流の判定でも50/50）。
  - 成功時の傾きは、中央値2.2°・最大3.9°。持ち上げ高さは23.5〜26.9cm。許容範囲に入るまでのステップ数は、中央値1351（位置の補正では1400）。
  - 位置の補正（46/50）との差は、Fisher の正確検定で p = 0.12 で、50回ずつでは有意ではない。物体の配置は実行ごとに無作為で、2つの評価で同じ配置を使ったわけではない。
