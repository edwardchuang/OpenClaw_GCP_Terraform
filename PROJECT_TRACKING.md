# **透過 Terraform 在 GCP 上安全部署 OpenClaw 環境**

本文件旨在追蹤使用 Terraform 基礎設施即代碼 (IaC) 在 Google Cloud Platform (GCP) 上自動化部署 OpenClaw AI 代理程式的步驟。此專案採用企業級的「零信任 (Zero-Trust)」安全架構，結合 GKE Autopilot、安全網頁代理 (SWP)、Cloud NGFW 與 Vertex AI Model Armor，確保 AI 工作負載在最高級別的安全隔離環境中運行。

## **工作項目追蹤**

| 工作項目 | 負責人 | 工作時間 | 狀態 | Notes |
| :---- | :---- | :---- | :---- | :---- |
| 專案追蹤與管理 | [Ethan Huang](mailto:ethuang@google.com) | 3 weeks | 進行中 |  |
| Terraform 模組與核心架構設計 | [Edward Chuang](mailto:pingda@google.com) | 2 weeks | ☑ 完成 | 包含 VPC, GKE, IAM 以及多實例 (Multi-instance) 模組化設計 |
| 零信任網路與 SWP/NGFW 安全代理實作 | [Edward Chuang](mailto:pingda@google.com) | 2 weeks | ☑ 完成 | Egress 流量管控，已導入 Cloud NGFW 與 Threat Intelligence |
| AI 安全防護 (Model Armor & SDP) 設計 | [Cory Hu](mailto:coryhu@google.com) | 2 weeks | ☑ 完成 | Prompt Injection 防護 |
| Docker 映像檔打包與 Artifact Registry | [Wayne An](mailto:waynean@google.com) | 1 weeks | ☑ 完成 | 已內建 Chromium 以支援自動化網頁瀏覽 |
| OpenClaw 技能 (Skills) 與 GCP 完美搭配 | [Owen Wu](mailto:ooowen@google.com) | 2 weeks | 進行中 | 網頁瀏覽能力已修復 |
| 基礎設施自動化部署驗證 | [Cory Hu](mailto:coryhu@google.com) | 1 weeks | ☑ 完成 | 支援有狀態 (Stateful) 與無狀態 (Ephemeral) 代理程式 |
| 架構白皮書與免責聲明文件編寫 | [Wayne An](mailto:waynean@google.com) | 1 weeks | ☑ 完成 | 確認開源與資安免責聲明 |

## **初始階段：企業級安全部署架構**

為了在 GCP 上建立一個兼具高擴展性、安全性與完全隔離的 OpenClaw 執行環境，本專案採用以下基於 GKE 的現代化雲端原生架構：

### **架構核心元件**

1. **全私有 VPC 網路 (Private VPC) 與 Cloud NGFW**  
   * **目的**：提供絕對私有的網路環境，阻斷所有來自外部網際網路的直接存取，並防禦進階威脅。  
   * **作法**：GKE 節點、Pod 及管理層 VM 皆不配置外部公網 IP (No Public IPs)。已導入 Cloud NGFW (Next-Generation Firewall) 結合 Google Cloud Threat Intelligence 進行深層網路防護與審計，主動阻擋惡意 IP 連線。
2. **Cloud NAT 與安全網頁代理 (Secure Web Proxy, SWP)**  
   * **目的**：精細化控制與審查傳出 (Egress) 流量。  
   * **作法**：底層 OS 更新透過 Cloud NAT；而 OpenClaw 應用程式產生的對外連線（包含無頭瀏覽器工具），則強制透過環境變數 `HTTPS_PROXY` 導向 Google Cloud SWP 進行 URL 級別的深層檢測與過濾。  
3. **GKE Autopilot 與多實例模組化架構 (支援 Stateful Agent)**  
   * **目的**：降低 Kubernetes 維運成本，並支援多個獨立、可選擇保留記憶的 OpenClaw 環境。  
   * **作法**：透過 Terraform Module 動態建立多個隔離的 OpenClaw 實例。您可以透過 `enable_persistence` 參數決定該代理程式是否具備長期記憶 (掛載 GKE Persistent Volume) 或是作為拋棄式沙盒運行。每個實例皆擁有專屬的內部 DNS 紀錄（如 `main.ui.openclaw.internal`）與內部負載平衡器。
4. **Vertex AI 深度安全防護 (Model Armor & SDP)**  
   * **目的**：防止提示詞注入攻擊 (Prompt Injection) 及機敏資料外洩 (Data Exfiltration)。  
   * **作法**：所有與 Gemini 3.1 Flash 等 Vertex AI 模型的互動，皆會經過 Model Armor 進行惡意操作攔截，並結合 Cloud DLP (Sensitive Data Protection) 掃描 PII 個資。  
5. **GCP Secret Manager (GSM) 與 CSI 驅動**  
   * **目的**：機敏資訊不落地，徹底告別環境變數明文金鑰。  
   * **作法**：每個實例擁有真實獨立的 Token 隔離 (true per-instance secret isolation)。系統會動態生成獨一無二的 Gateway Token 統一存放在 GSM，並透過 CSI Driver 自動掛載至對應的 GKE Pod 中。  
6. **IAP (Identity-Aware Proxy) 堡壘機**  
   * **目的**：無公網 IP 的情況下安全存取內部服務及 Web UI。  
   * **作法**：建置 Bastion Host，透過 gcloud IAP 建立加密安全通道，再透過 Port Forwarding 存取內部負載平衡器上各實例專屬的 OpenClaw UI。

## **第一階段：基礎設施即代碼 (IaC) 建置**

此階段目標是透過 Terraform 自動化建立 GCP 上的所有底層基礎設施。

| 任務 | 狀態 | 負責人 | 預計完成日期 | 相關說明 |
| :---- | :---- | :---- | :---- | :---- |
| 1\. 初始化 Terraform Backend | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 執行 `00-bootstrap.tf` 建立儲存 State 的 GCS Bucket。 |
| 2\. 啟用 GCP API 服務 | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 啟用 GKE, Vertex AI, Secret Manager, SWP 等 API (`01-apis.tf`)。 |
| 3\. 建立 VPC, 網路拓樸與 NGFW | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 部署子網路、Cloud NAT、防火牆規則與 Cloud NGFW (`02-network.tf`, `04-firewall.tf`, `11-ngfw.tf`)。 |
| 4\. 配置 Secure Web Proxy | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 建立 SWP 實例以過濾對外連線 (`03-swp.tf`)。 |
| 5\. 建立 GKE Autopilot 叢集 | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 部署具備私有節點的高安全 Kubernetes 叢集 (`07-gke.tf`)。 |
| 6\. 部署 IAP 堡壘機 (Bastion) | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 提供安全存取內網的跳板機 (`05-bastion.tf`)。 |

### **任務詳情：**

#### **1\. 初始化 Terraform Backend**
前往 `terraform/` 目錄，首先套用 bootstrap 配置來建立管理狀態檔的 Cloud Storage Bucket，隨後將其名稱更新至 `backend.tf` 以便團隊協作：
```bash
cd terraform/
terraform init
terraform apply -target=module.bootstrap
```

#### **5\. 建立 GKE Autopilot 叢集**
Terraform 將自動建立一個全私有的 GKE Autopilot 叢集，並綁定專屬的 Workload Identity 服務帳號，實現最小權限原則 (Least Privilege)，確保 Pod 僅能存取其被授權的 GCP 資源（如 Secret Manager）。

## **第二階段：OpenClaw 應用部署與配置**

基礎設施就緒後，將透過客製化 Docker 映像檔與 Terraform 模組完成 OpenClaw 應用程式部署。

| 任務 | 狀態 | 負責人 | 預計完成日期 | 相關說明 |
| :---- | :---- | :---- | :---- | :---- |
| 1\. 建立 Artifact Registry | ☑ | [Wayne An](mailto:waynean@google.com) | 已完成 | 執行 `10-registry.tf` 建立私有容器映像檔庫。 |
| 2\. 打包客製化 Docker Image | ☑ | [Wayne An](mailto:waynean@google.com) | 已完成 | 使用 `docker-build/` 目錄下的腳本打包並推送映像檔 (已包含 Chromium 支援)。 |
| 3\. 在 Secret Manager 設定金鑰 | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 透過 Terraform 動態生成並寫入獨立的 Gateway Token。 |
| 4\. 設定 Terraform 變數 (tfvars) | ☑ | [Edward Chuang](mailto:pingda@google.com) | 已完成 | 透過 Terraform Module 架構宣告 OpenClaw 實例及其儲存策略。 |
| 5\. 執行 Terraform Apply | ☑ | [Cory Hu](mailto:coryhu@google.com) | 已完成 | 自動化部署 GKE Workloads、Service 與內部負載平衡器 (`08-app.tf`)。 |

### **任務詳情：**

#### **2\. 打包客製化 Docker Image**
OpenClaw 及預先安裝的 Skills 會被打包成單一容器。進入 `docker-build/` 目錄執行建置指令：
```bash
./build.sh <your-project-id>
```

#### **4 & 5\. 執行自動化部署**
編輯 `terraform/terraform.tfvars`，宣告您的 OpenClaw 實例與記憶持久化策略 (Persistence)：
```hcl
openclaw_instances = {
  "main" = {
    image              = "us-central1-docker.pkg.dev/your-project/openclaw-repo-prod/openclaw-custom:v1.0.0"
    enable_persistence = true   # 啟用持久化儲存，保留對話歷史與記憶
    storage_size       = "10Gi" # 設定磁碟大小
  }
  
  "research-bot" = {
    image              = "us-central1-docker.pkg.dev/your-project/openclaw-repo-prod/openclaw-custom:v1.0.0"
    enable_persistence = false  # 拋棄式沙盒環境，重啟後將失去所有記憶
  }
}
```
接著執行部署：
```bash
terraform init
terraform plan
terraform apply
```

## **第三階段：驗證里程碑**

| 里程碑 | 狀態 | 預計完成日期 | 備註 |
| :---- | :---- | :---- | :---- |
| 成功套用 Terraform 並無報錯 | ☑ |  | 所有基礎設施與 Kubernetes 資源順利建立。 |
| 驗證 GKE Pod 狀態為 Running | ☑ |  | 確認 OpenClaw 容器成功啟動且未陷入 CrashLoopBackOff。 |
| 透過 IAP 堡壘機安全存取 Web UI | ☑ |  | 能夠藉由 SSH Port Forwarding 連接至內部 Load Balancer 並開啟控制台。 |
| Model Armor 與通訊軟體串接測試 | ☐ |  | 驗證機器人能正常回覆，且惡意提示詞注入 (Prompt Injection) 會被 GCP 成功阻擋。 |

### **安全存取 Web UI 測試方式**
每個實例都擁有獨一無二的存取金鑰與內部 DNS 解析名稱。

1. 取得 Terraform 動態生成的 Gateway Tokens 列表：
   `terraform output -json gateway_tokens`
2. 建立 IAP 安全通道 (Port Forwarding)，請將 DNS 名稱替換為您欲存取的實例（例如 `main` 或 `research-bot`）：
   `gcloud compute ssh openclaw-bastion-prod --tunnel-through-iap --zone us-central1-a --project <your-project-id> -- -N -L 18789:main.ui.openclaw.internal:18789`
3. 打開瀏覽器訪問 `http://localhost:18789`，並輸入步驟一取得的對應 Token，即可以極高的安全性管理您的 OpenClaw。

## **第四階段：安全性強化與合規 (已內建)**

此 Terraform 範本已在架構底層實踐了嚴格的安全防護，以下為安全機制的重點盤點：

| 任務 / 機制 | 狀態 | 負責人 | 預計完成日期 | 相關說明 |
| :---- | :---- | :---- | :---- | :---- |
| 1\. GKE 網路策略 (Network Policies) | ☑ |  |  | 預設限制叢集內部跨 Namespace 或非必要 Pod 間的連線。 |
| 2\. 機密資料不落地 (CSI Secret Store) | ☑ |  |  | Pod 不透過環境變數傳遞密碼，直接將 Secret Manager 金鑰掛載為唯讀檔案。 |
| 3\. IAM 權限最小化 (Workload Identity) | ☑ |  |  | 每個 OpenClaw 實例只擁有讀取自己專屬金鑰、以及存取限定 Vertex AI 模型的權限。 |
| 4\. 本地端服務安全綁定 (Socat Sidecar) | ☑ |  |  | OpenClaw 預設綁定本地端，利用 Socat Sidecar 容器安全地將流量導出至內部網路。 |
| 5\. 審計與監控 (Cloud Audit Logs) | ☑ |  |  | 啟用完整的存取紀錄與 Kubernetes API 審計日誌。 |
| 6\. Cloud NGFW 威脅防禦 | ☑ |  |  | 在 VPC 邊界部署 Cloud NGFW，結合 GCTI 進行即時威脅攔截。 |

## **第五階段：GCP 整合技能開發 (Creative Ideas)**

在企業級安全環境建置完成後，可透過開發與 GCP 深度整合的 OpenClaw Skills，打造全自動化的雲端維運助理。

| 技能發想 | 核心功能 | 應用情境 |
| :---- | :---- | :---- |
| **GCE/GKE 資源報告員** | 透過 GCP API 查詢並定時回報專案的 VM、Pod 運行狀態及效能指標。 | "Claw, 幫我查一下 production 環境 GKE 叢集的節點使用率。" |
| **Cloud Storage 智慧清理員** | 掃描指定的 GCS Bucket，找出過期暫存檔案，經過確認後自動執行清理。 | "Claw, 檢查 temp-data-bucket 有沒有超過 90 天未存取的日誌檔並刪除。" |
| **Cloud Billing 預算守望者** | 串接 Billing API，每日檢查專案花費，當預算水位超過 80% 時主動透過 Telegram 警示。 | "Claw, 每天早上發送一份本月 GCP 花費與預測報告給我。" |
| **Error Reporting 警報分析師** | 當應用程式發生錯誤時，自動抓取 Cloud Logging，並利用 Vertex AI 進行初步 RCA (根因分析)。 | "Claw, backend-api 的 5xx 錯誤率飆高了，幫我總結一下最新的 Error Log。" |
| **IAM 權限查詢與合規稽核** | 查詢特定使用者的 IAM 角色，或定期掃描是否有被過度授權 (如 Project Owner) 的高風險帳號。 | "Claw, 幫我查一下有哪些外部信箱擁有我們專案的編輯者權限？" |
| **架構圖表與文件生成器** | 結合 Vertex AI Gemini 的多模態能力，將部署日誌或 Terraform 規劃結果總結為易讀的技術文件。 | "Claw, 把這段 Terraform Plan 輸出總結成三點可能造成的變更風險。" |

---

> **注意事項**：此 Terraform 佈署方案不包含 SLA 保證，請確保您在將此架構推廣至生產環境前，已經過內部資安團隊及法務人員的評估與確認。
## **總體擁有成本 (TCO) 估算分析**

本節提供在 Google Cloud Platform (GCP) 上運行安全 OpenClaw 代理程式基礎設施的預估每月總體擁有成本 (TCO)。此計算以 `us-central1` 區域為基準，並假設一個月為 730 小時。

> **注意：** 價格為基於 2026 年初標準 GCP 公開定價的估算值。實際成本可能會因使用量、折扣及層級變更而有所不同。

### 1. 基礎設施基線成本 (每月固定)

這代表了維持「零信任金庫 (Zero-Trust Vault)」的固定維運成本，與您與 AI 代理程式的互動頻率無關。

| 元件 | 說明 | 預估成本 / 月 (USD) |
| :--- | :--- | :--- |
| **Cloud NGFW Enterprise** | 進階 L4 防火牆，具備 Google Cloud Threat Intelligence 與 IPS。（$1.75/小時 每個端點） | **$1,277.50** |
| **Private CA Service** | 企業層級，用於 Secure Web Proxy 的 TLS 深度檢測。 | **$400.00** |
| **Secure Web Proxy (SWP)** | 專用的 L7 代理伺服器，用於對外 AI 流量審計。（$0.35/小時） | **$255.50** |
| **GKE Autopilot** | 叢集管理費。（$0.10/小時） | **$73.00** |
| **GKE Compute (Agent Pod)** | 單一代理程式實例 (1 vCPU, 4GB RAM) 持續運行。 | **~$35.00** |
| **Cloud NAT** | 標準 NAT 閘道器，用於基礎節點對外連線。（$0.045/小時） | **$32.85** |
| **Bastion Host** | `e2-micro` 實例，用於 IAP 隧道連線（通常涵蓋在免費額度內）。 | **$7.00** |
| **Persistent Storage** | 10GB 標準 PD，用於儲存代理程式狀態/記憶。 | **$0.40** |
| **Secret Manager** | 用於儲存 Gateway 與 Channel Token。 | **$0.12** |
| **Cloud Logging** | 首 50GB 免費。小型部署的審計日誌通常會在此限制內。 | **$0.00** |
| --- | --- | --- |
| **基線成本總計** | **企業級零信任隔離的防護代價。** | **~$2,081.37 / 月** |

#### 📉 成本優化策略
基線成本主要來自進階安全功能 (NGFW Enterprise 與 Private CA)。如果在非生產環境或較不關鍵的環境中部署，您可以大幅降低此基線：
*   **移除 NGFW Enterprise：** 僅依賴標準 VPC 防火牆可節省 **$1,277.50**。
*   **移除 Private CA & SWP TLS Inspection：** 略過 URL 級別的深度審計可節省 **$655.50**。
*   **優化基線：** 僅運行 GKE Autopilot + 標準 NAT + Cloud SQL（如有添加），基礎設施成本將降至 **約 $150 / 月**。

### 2. AI 模型與安全性變動成本

這是基於使用量的成本，當 OpenClaw 代理程式主動處理任務、抓取網頁或回答查詢時產生。以下計算以 **Gemini 3.1 Flash-Lite** 為基準（若使用 Gemini 3 Flash，輸入為 $0.50，輸出為 $3.00）。

#### 單位成本 (每 100 萬 Tokens)
*   **Gemini 3.1 Flash-Lite (輸入)：** $0.25 / 1M Tokens
*   **Gemini 3.1 Flash-Lite (輸出)：** $1.50 / 1M Tokens
*   **Model Armor (SDP 掃描)：** ~$4.00 / 1M Tokens (基於 1MB 資料的 PII 檢測掃描成本)

#### 「混合 Token」公式
一個典型的 AI 代理程式任務包含龐大的上下文視窗 (系統提示詞、載入的網頁、過去的記憶) 以及較小的生成輸出。

假設一個典型交易的比例為 **95% 輸入 / 5% 輸出**：
*   輸入成本: $0.25 * 0.95 = $0.2375
*   輸出成本: $1.50 * 0.05 = $0.075
*   Model Armor 成本: $4.00 (每個進出的 Token 皆需被掃描)

**混合 AI 總成本 = $4.3125 USD / 每 100 萬 Tokens**

> **洞察：** 在此高度安全的架構中，*檢測*資料中機敏資訊 (Model Armor) 的成本大約是 AI 模型*生成與讀取*回應成本的 **12 倍**。

### 3. TCO 總公式

如需估算您每月的總花費，請使用以下公式：

**$$ \text{總成本} = \$2,081.37 + \left( \frac{\text{每月總 Tokens}}{1,000,000} \times \$4.3125 \right) $$**

#### 範例情境
一位企業 IT 管理員使用代理程式每月總結 50 份內部事件報告並閱讀 100 頁的 GCP 說明文件，剛好消耗了 **1,000 萬 (10 Million) Tokens**。

*   基礎設施基線: $2,081.37
*   AI 使用量: 10 * $4.3125 = $43.13
*   **每月總帳單: $2,124.50**
