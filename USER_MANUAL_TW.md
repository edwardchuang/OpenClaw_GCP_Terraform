# **在 GCP 上使用 Terraform 部署 OpenClaw 企業級安全環境**

本指南專為 **GCP 與 Terraform 的初學者**設計，提供將 OpenClaw AI 代理程式部署至具備企業級「零信任 (Zero-Trust)」安全架構的標準作業流程 (SOP)。透過基礎設施即代碼 (IaC) 的方式，確保環境配置具備高度安全性與可重製性。

---

## **事前準備：系統與工具需求**

在開始部署前，請確保您的開發環境已安裝並配置以下工具：

1. **Google Cloud 帳號**：需具備 GCP 存取權限 (新註冊用戶通常享有免費試用額度)。
2. **Google Cloud CLI (`gcloud`)**：GCP 命令列管理工具，請參考 [官方安裝指南](https://cloud.google.com/sdk/docs/install)。
3. **Terraform**：基礎設施配置工具，請前往 [Terraform 下載頁面](https://developer.hashicorp.com/terraform/downloads) 安裝版本 1.5 以上。
4. **Git**：用於複製專案原始碼。
5. **Docker (選用)**：若需建置包含客製化技能 (Skills) 的 OpenClaw 容器映像檔，請預先安裝。

---

## **第一階段：建立 GCP 專案與環境初始化**

所有 GCP 資源皆需隸屬於特定專案 (Project)。請依下列步驟建立並初始化部署環境。

### **步驟 1：登入 Google Cloud**
於終端機 (Terminal / 命令提示字元) 執行以下指令進行身分驗證：
```bash
gcloud auth login
```
系統將開啟瀏覽器，請使用您的 Google 帳號登入並授權存取。

### **步驟 2：建立新專案**
設定您的專案 ID (需全域唯一，僅限小寫字母、數字及連字號，例如 `my-openclaw-sec-123`)：
```bash
# 定義專案 ID 變數
PROJECT_ID="my-openclaw-sec-123"

# 建立專案
gcloud projects create $PROJECT_ID

# 設定 CLI 預設專案
gcloud config set project $PROJECT_ID
```

### **步驟 3：綁定計費帳戶 (Billing)**
此架構依賴進階服務 (如 GKE, Cloud NGFW, SWP)，專案必須啟用計費功能。
1. 前往 [GCP 控制台 - 帳單頁面](https://console.cloud.google.com/billing)。
2. 確認已建立計費帳戶。
3. 將新建立的專案 (`my-openclaw-sec-123`) 連結至該計費帳戶。

---

## **第二階段：下載專案與 Terraform 變數配置**

取得基礎設施代碼並配置環境專屬參數。

### **步驟 1：複製專案原始碼**
於終端機執行：
```bash
git clone https://github.com/edwardchuang/OpenClaw_GCP_Terraform.git
cd OpenClaw_GCP_Terraform
```

### **步驟 2：設定 Terraform 變數 (`terraform.tfvars`)**
複製範例設定檔以建立本地變數設定：
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```
開啟 `terraform/terraform.tfvars`，根據您的環境修改參數：
```hcl
project_id = "YOUR_PROJECT_ID_HERE"  # 填入您的專案 ID
region     = "us-central1"           # 預設部署區域

openclaw_instances = {
  "main" = {
    image              = "us-central1-docker.pkg.dev/YOUR_PROJECT_ID_HERE/openclaw-repo-prod/openclaw-custom:v1.0.0"
    enable_persistence = true   # true: 啟用持久化儲存；false: 無狀態沙盒環境
    storage_size       = "10Gi" 
  }
}
```
**注意：** 請務必將檔案中的 `YOUR_PROJECT_ID_HERE` 替換為您在第一階段建立的專案 ID。

---

## **第三階段：Terraform 一鍵部署**

Terraform 將為您自動建置包含私有網路、防火牆、安全代理、GKE 叢集以及金鑰管理員的完整基礎設施。

### **步驟 1：初始化 Terraform 狀態儲存桶 (Backend)**

Terraform 需要一個雲端儲存桶 (GCS Bucket) 來記錄部署狀態。由於該儲存桶也是透過 Terraform 建立的資源之一，我們需要分兩步進行初始化：

1. **暫時將狀態存放在本機**：
   打開 `terraform/backend.tf` 檔案。將裡面的內容註解掉（在最前面加上 `/*`，最後面加上 `*/`）。
   ```hcl
   /*
   terraform {
     backend "gcs" {
       bucket = "claw-platform-01-tfstate"
       prefix = "terraform/openclaw/state"
     }
   }
   */
   ```
2. **建立專用的儲存桶**：
   在終端機中執行以下指令，優先建立此儲存桶：
   ```bash
   cd terraform
   terraform init
   terraform apply -target=google_storage_bucket.terraform_state
   ```
   *當畫面詢問 `Do you want to perform these actions?` 時，請輸入 `yes`。*

3. **啟用雲端狀態儲存 (Backend)**：
   上述指令已建立一個名為 `openclaw-tfstate-[您的專案ID]-prod` (例如 `openclaw-tfstate-my-openclaw-sec-123-prod`) 的儲存桶。
   回到 `backend.tf`，移除註解 (`/*` 與 `*/`)，並將 `bucket` 更新為您剛建立的儲存桶名稱：
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "openclaw-tfstate-my-openclaw-sec-123-prod" # 請替換為您的 bucket 名稱
       prefix = "terraform/openclaw/state"
     }
   }
   ```

### **步驟 2：全面部署基礎設施**

正式將架構部署至雲端：

```bash
terraform init  # 再次初始化，當系統詢問是否將本機狀態轉移至雲端時，請輸入 yes
terraform plan  # 預覽準備建立的資源
```

確認預覽內容無誤後，執行最終部署：

```bash
terraform apply
```
*輸入 `yes` 以確認執行。*

☕ **喝杯咖啡休息一下**：這個過程大約需要 15~20 分鐘。Terraform 正在為您建立高安全的 GKE Autopilot 叢集、設定次世代防火牆 (NGFW) 和內部網路。

---

## **第四階段：打包與部署 OpenClaw 應用程式**

基礎設施建置完成後，接下來需部署 OpenClaw 應用服務。

### **步驟 1：打包 Docker 映像檔**
我們需要將 OpenClaw 與其依賴的技能 (Skills) 打包成容器映像檔，並推送到 GCP 專案內的私有容器儲存庫 (Artifact Registry)。

開啟新的終端機視窗（請保持在專案根目錄）。在執行腳本前，我們必須先更新腳本內的專案 ID，並登入 Docker 儲存庫：

1. 開啟 `docker-build/build.sh` 檔案。
2. 將前方的 `PROJECT_ID="claw-platform-01"` 替換為您自己的專案 ID（例如 `PROJECT_ID="my-openclaw-sec-123"`）。
3. 存檔後，執行以下指令授權 Docker 推送映像檔至 GCP，並執行打包腳本：

```bash
cd docker-build
gcloud auth configure-docker us-central1-docker.pkg.dev
./build.sh
```
*此腳本將自動建置映像檔並上傳至 GCP。*

### **步驟 2：部署容器至 GKE**
回到原先執行 Terraform 的終端機視窗 (確認位於 `terraform/` 目錄下)。若上述的 `terraform apply` 已成功完成，OpenClaw 容器應已開始在 GKE 叢集中啟動。

*(備註：若稍早執行 Terraform 時，因容器映像檔尚未上傳而發生錯誤，請在此時重新執行 `terraform apply` 即可。)*

---

## **第五階段：安全連線與存取驗證**

基於**零信任架構**的設計，OpenClaw 實例未配置任何外部公開 IP。您必須建立 IAP (Identity-Aware Proxy) 安全隧道才能存取控制台。

### **步驟 1：取得專屬登入金鑰 (Gateway Token)**
Terraform 已自動為每個 OpenClaw 實例生成高強度的隨機密碼，並安全地儲存於 GCP Secret Manager。

在 `terraform/` 目錄下執行以下指令以獲取金鑰：
```bash
terraform output -json gateway_tokens
```
指令將輸出 JSON 格式的金鑰對應表，例如 `"main": "sk-xxxxx..."`。請複製該 `sk-` 開頭的字串以供後續登入使用。

### **步驟 2：建立安全隧道 (IAP Tunnel)**
執行以下指令，透過堡壘機 (Bastion Host) 建立通往雲端內網的安全隧道：
```bash
# 請務必將 project 替換為您的專案 ID
gcloud compute ssh openclaw-bastion-prod \
    --tunnel-through-iap \
    --zone us-central1-a \
    --project my-openclaw-sec-123 \
    -- -N -L 18789:main.ui.openclaw.internal:18789 
```
*若系統提示建立 SSH 金鑰，按 Enter 接受預設值即可。*

**注意：** 指令執行後終端機會處於停留狀態 (不會有成功提示)，這表示隧道已成功建立並正在運行，請**保持此視窗開啟**。

### **步驟 3：登入 Web 介面**
現在，請開啟網頁瀏覽器並前往：
**`http://localhost:18789`**

在 OpenClaw 的登入畫面中，輸入您在**步驟 1** 取得的 Gateway Token。

🎉 **部署完成：** 您已成功在 Google Cloud 上建置並登入具備企業級資安防護的 AI 代理程式環境。

---

## **常見問題 (FAQ)**

**Q: 無法連線至 `http://localhost:18789`？**
A: 請確認您的「安全隧道 (IAP Tunnel)」終端機視窗是否仍在執行中。若連線中斷，請重新執行該 `gcloud compute ssh` 指令。此外，請確認您欲存取的實例名稱 (例如 `main`) 與指令中的 DNS 解析名稱 (`main.ui.openclaw.internal`) 相符。

**Q: 如何徹底銷毀資源以停止計費？**
A: 為了避免產生不必要的費用，您可以隨時使用 Terraform 銷毀所有資源。在 `terraform/` 目錄下執行：
```bash
terraform destroy
```
輸入 `yes` 確認後，Terraform 將自動並安全地拆除其建立的所有基礎設施。

**Q: Terraform 變數中的「有狀態 (Stateful)」與「無狀態 (Ephemeral)」有何差異？**
A: 位於 `terraform.tfvars` 中的設定：
*   `enable_persistence = true`：為實例配置永久儲存磁碟 (Persistent Disk)。代理程式重啟後仍會保留對話歷史與學習記憶。
*   `enable_persistence = false`：實例作為無狀態的沙盒 (Sandbox) 運行。適用於執行高風險任務或資安研究，重啟後環境將完全重置。
