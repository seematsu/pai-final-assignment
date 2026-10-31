# LabUtopia 静的セキュリティ確認（2026-10-24）

対象は `repo/` のコミット `8df72784265c375a327ffa3f0a0cf8c676f229a7` とLFSのアセットです。確認はすべて、コードを実行する前に行いました。

| 確認項目 | 結果 |
|---|---|
| バイナリ・実行ファイル | ELF・PE・Mach-O・pickle・zip・whlなどは含まれない。実行ビットが立っているのは、READMEとMDL（マテリアルの記述）だけ |
| 危険な処理 | `subprocess` は、テスト用スクリプトとACTのgit SHA取得（DETR由来）だけ。`OmegaConf` の `eval` リゾルバに渡るのは、同梱yaml内の `${eval:'${n_obs_steps}-1+...'}` という数値計算だけ。`torch.load` と `pickle` は、自分が学習したチェックポイントを読むためだけに使われる |
| 通信 | 通信するのは、openpi-client（リモート推論用のwebsocket）だけ。同梱版は本家のコミット `b69c6e3` と、改行コード（CRLF）以外は完全に同じ |
| 難読化 | base64のblob、不可視文字、異常に長いコード行はない（400文字を超える行は、言語指示の文字列が1行だけ） |
| ファイル操作 | 削除は、自分が作った出力エピソードとチェックポイントに限られる。`config/level3_open.yaml` に作者の環境の絶対パス（`/home/ubuntu/...`）が残っているが、読み込み専用の再生用設定 |
| USDアセット | 27レイヤをpxrで解析した。OmniGraphのノード、スクリプト属性、Pythonのカスタムデータはない。外部の参照は、NVIDIA公式S3のSektion Cabinet 1件だけ |
| 依存パッケージ | 取得元は、pypi.org、pypi.nvidia.com、download.pytorch.org（cu130）だけ。194パッケージに不審な名前はない（Isaac Simが使うAWS・Azureのクライアントを含む） |
| 注意点 | アセットの利用条件について、商用デモへの利用を問い合わせるIssue（#15）が未回答のまま残っている。リポジトリ自体のライセンスはMIT |
