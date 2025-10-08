# MCPServer_NWTroubleShoot

MCP Server that troubleshooting target network

📘 概要

このリポジトリは、Claude による MCP（Model Context Protocol）連携の PoC 環境を中心に構築された、
ネットワークトラブルシュート自動化検証用コードです。
AWX（Ansible Tower）、ContainerLab、VyOS を組み合わせ、
show コマンドを安全に実行し、結果を MCP 経由で解析することを目的としています。

🧩 ディレクトリ構成
MCPServer_NWTroubleShoot/
├─ mcp-awx/ # MCP サーバ本体（Claude 連携のエントリポイント）
│ ├─ server.py # MCP サーバ
│ ├─ .env # AWX 接続設定 (URL / Token / JobTemplate ID 等)
│ ├─ **pycache**/
│
├─ awx/ # AWX 実行環境（Ansible Execution Environment）
│ ├─ Dockerfile.awx-ee-vyos
│ ├─ execution-environment.yml
│ ├─ requirements.txt / requirements.yml
│ └─ context/
│
├─ container-lab/ # ContainerLab 構成と検証用 playbook 群
│ └─ lab1/
│ ├─ lab1.yml
│ ├─ show.yml / show_pretty.yml
│ ├─ inventory.yml / vault.yml
│ └─ configs/, results/, ansible.cfg
│
├─ vyos/ # VyOS ISO → Docker イメージ化スクリプトとビルド資材
│ ├─ Dockerfile
│ ├─ vyos_build.sh
│ ├─ rootfs.tar
│ ├─ vyos-\*.iso
│ └─ live/
│
└─ README.md # 本ファイル

⚙️ 環境構築と実行
1️⃣ VyOS イメージビルド
cd vyos
./vyos_build.sh --iso ./vyos-2025.10.01-0021-rolling-generic-amd64.iso \
 --tag vyos:rolling-2025.10.01

ISO から rootfs を抽出し、FROM scratch ベースで Docker 化。
ContainerLab で利用可能な軽量 VyOS コンテナを生成。

2️⃣ ContainerLab 起動
cd container-lab/lab1
sudo containerlab deploy -t lab1.yml

VyOS ノードを複数起動し、Ansible/AWX から show コマンドを投げて状態を収集。

3️⃣ AWX 実行環境（EE）ビルド
cd awx
docker build -t awx-ee-vyos -f Dockerfile.awx-ee-vyos .

vyos.vyos コレクションや paramiko などを含んだ EE を作成。

4️⃣ MCP サーバ（mcp-awx）の起動
cd mcp-awx
pip install -r requirements.txt # （または uv / poetry 等で管理）
python server.py

.env 例：

AWX_URL=https://awx.local
AWX_TOKEN=<your-awx-api-token>
AWX_TEMPLATE_ID=9

Claude や他の MCP クライアントからこのサーバを叩くことで、
AWX ジョブテンプレート経由で安全に show コマンドを実行・収集できる。

🧠 検証目的

Claude + AWX MCP による NW トラブルシュートの自動化 PoC
