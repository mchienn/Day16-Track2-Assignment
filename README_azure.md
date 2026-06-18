# Hướng dẫn Thực hành LAB 16: Cloud AI Environment Setup (2.5h) - Phiên bản Microsoft Azure

Chào mừng các bạn đến với Lab 16 phiên bản Microsoft Azure. Trong bài thực hành này, chúng ta sẽ thiết lập một môi trường Cloud AI hoàn chỉnh trên Azure bằng cách sử dụng **Terraform** (Infrastructure as Code) và **Docker/vLLM**.

Mục tiêu của bài lab là triển khai mô hình ngôn ngữ lớn (`google/gemma-4-E2B-it`) lên một máy chủ GPU (NVIDIA T4) nằm an toàn trong mạng nội bộ (Private VNet), và cung cấp API truy cập ra bên ngoài thông qua Load Balancer.

---

## Phần 1: Chuẩn bị tài khoản Azure và thiết lập Service Principal (Least-Privilege)

Trên Azure, mọi tài nguyên đều thuộc về một **Subscription**. Bạn cần tạo một Service Principal với quyền vừa đủ (least-privilege) để Terraform có thể triển khai hạ tầng.

### Bước 1.1: Đăng nhập Azure Portal
1. Truy cập [Azure Portal](https://portal.azure.com/).
2. Đăng nhập bằng tài khoản Microsoft (tài khoản cơ quan hoặc tài khoản cá nhân).
3. Đảm bảo bạn đang ở trong đúng **Subscription** muốn sử dụng (xem trên thanh trên cùng, cạnh avatar).

### Bước 1.2: Tạo Service Principal cho Terraform

**Cách 1: Dùng Azure Portal**
1. Trong Azure Portal, tìm kiếm **Microsoft Entra ID** và chọn.
2. Menu trái chọn **Applications** -> **App registrations** -> nhấn **New registration**.
3. Điền **Name**: `ai-lab-terraform`, chọn **Accounts in this organizational directory only** -> nhấn **Register**.
4. Copy **Application (client) ID** và **Directory (tenant) ID**.
5. Vào **Certificates & secrets** -> **New client secret** -> copy **Value** (chỉ xem 1 lần).

**Cách 2: Dùng Azure CLI (nhanh hơn)**
```bash
# Đăng nhập
az login

# Tạo Service Principal và gán quyền Contributor (tự động)
az ad sp create-for-rbac \
  --name "ai-lab-terraform" \
  --role "Contributor" \
  --scopes "/subscriptions/$(az account show --query id -o tsv)"
```
Kết quả trả về类似 thế này — copy và lưu lại:
```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName": "ai-lab-terraform",
  "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```
- `appId` → `ARM_CLIENT_ID`
- `password` → `ARM_CLIENT_SECRET`
- `tenant` → `ARM_TENANT_ID`

### Bước 1.3: Tăng hạn mức vCPU cho GPU (Rất quan trọng)
Theo mặc định, Azure có thể giới hạn số lượng VM GPU trong một Subscription. Bạn cần kiểm tra và yêu cầu tăng quota:

**Cách 1: Dùng Azure Portal**
1. Trong Azure Portal, tìm **Subscriptions** và chọn Subscription của bạn.
2. Menu trái chọn **Usage + quotas**.
3. Tìm kiếm `Standard NCASv3-Type` hoặc `NC T4` series.
4. Nếu quota hiện tại < 1 (vCPU cần cho `Standard_NC4as_T4_v3`), nhấn **Request increase** và yêu cầu ít nhất **12 vCPU**.

**Cách 2: Dùng Azure CLI**
```bash
# Xem danh sách quota hiện tại
az vm list-usage --location eastus --query "[?contains(name.value, 'NC') || contains(name.value, 'T4')]" --output table

# Hoặc xem tất cả quota GPU
az vm list-usage --location eastus --query "[?name.value=='standardNCSv3Family']" --output table
```
*Lưu ý: Azure có thể mất từ vài phút đến vài giờ để duyệt yêu cầu này.*

> **⚠️ Ghi chú quan trọng cho tài khoản mới / Free Trial:** Nếu yêu cầu tăng quota GPU bị từ chối hoặc chưa được duyệt trong thời gian làm lab, hãy chuyển sang **[Phần 7: Phương án Dự phòng — CPU Instance với LightGBM](#phần-7-phương-án-dự-phòng--cpu-instance-với-lightgbm-khi-không-xin-được-quota-gpu)**. Đây là phương án thay thế hợp lệ và sẽ được chấm điểm tương đương.

---

## Phần 2: Cài đặt và cấu hình môi trường Local

Trên máy tính cá nhân của bạn, mở Terminal/Command Prompt.

### Bước 2.1: Cài đặt Azure CLI
Đảm bảo bạn đã cài đặt [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli). Kiểm tra bằng lệnh:
```bash
az --version
```

### Bước 2.2: Đăng nhập Azure qua CLI
Mở Terminal và chạy lệnh:
```bash
az login
```
Trình duyệt sẽ mở ra, bạn đăng nhập bằng cùng tài khoản Azure Portal. Sau khi đăng nhập thành công, chọn Subscription muốn sử dụng:
```bash
# Liệt kê các Subscription
az account list --output table

# Chọn Subscription (thay subscription_id)
az account set --subscription "<SUBSCRIPTION_ID_CỦA_BẠN>"
```

### Bước 2.3: Cấu hình Environment Variables cho Terraform
Thiết lập các biến môi trường để Terraform xác thực và triển khai trên Azure:
```bash
# Windows (PowerShell)
$env:ARM_CLIENT_ID="<APPLICATION_CLIENT_ID_CỦA_BẠN>"
$env:ARM_CLIENT_SECRET="<CLIENT_SECRET_VALUE_CỦA_BẠN>"
$env:ARM_SUBSCRIPTION_ID="<SUBSCRIPTION_ID_CỦA_BẠN>"
$env:ARM_TENANT_ID="<DIRECTORY_TENANT_ID_CỦA_BẠN>"
$env:TF_VAR_hf_token="<DÁN_TOKEN_HUGGING_FACE_CỦA_BẠN>"
$env:TF_VAR_admin_password="<MẬT_KHẨU_ADMIN_CHO_VM>"

# Linux/Mac
export ARM_CLIENT_ID="<APPLICATION_CLIENT_ID_CỦA_BẠN>"
export ARM_CLIENT_SECRET="<CLIENT_SECRET_VALUE_CỦA_BẠN>"
export ARM_SUBSCRIPTION_ID="<SUBSCRIPTION_ID_CỦA_BẠN>"
export ARM_TENANT_ID="<DIRECTORY_TENANT_ID_CỦA_BẠN>"
export TF_VAR_hf_token="<DÁN_TOKEN_HUGGING_FACE_CỦA_BẠN>"
export TF_VAR_admin_password="<MẬT_KHẨU_ADMIN_CHO_VM>"
```

### Bước 2.4: Lấy Hugging Face Token
Mô hình `google/gemma-4-E2B-it` là một mô hình bị giới hạn (gated model).
1. Đăng nhập [Hugging Face](https://huggingface.co/).
2. Vào trang mô hình [google/gemma-4-E2B-it](https://huggingface.co/google/gemma-4-E2B-it) và đồng ý với điều khoản (Accept license).
3. Vào **Settings** -> **Access Tokens** -> Tạo một token (quyền Read) và copy lại.

---

## Phần 3: Triển khai Hạ tầng với Terraform

Kiến trúc AI Server trên Azure bao gồm:
- **Virtual Network (VNet)**: Mạng riêng chứa Public Subnet và Private Subnet.
- **Public Subnet**: Chứa Bastion Host (Standard_B2s) làm trạm trung chuyển SSH an toàn.
- **Private Subnet**: Chứa GPU Node (Standard_NC4as_T4_v3 - NVIDIA T4), không có Public IP.
- **NAT Gateway**: Cho phép Private Subnet truy cập internet để tải Docker image và Model.
- **Network Security Group (NSG)**: Kiểm soát truy cập - chỉ cho phép SSH từ Bastion và HTTP từ Load Balancer vào GPU Node.
- **Azure Load Balancer**: External LB nhận request từ internet và chuyển vào port 8000 của GPU Node.

### Bước 3.1: Khởi tạo Terraform
Di chuyển vào thư mục code Terraform Azure:
```bash
cd terraform-azure
terraform init
```

### Bước 3.2: Triển khai (Apply)
Chạy lệnh apply để Terraform tạo toàn bộ tài nguyên trên Azure:
```bash
terraform apply
```
Gõ `yes` khi được hỏi. Quá trình triển khai hạ tầng trên Azure thường mất khoảng **5-10 phút**.

*Mẹo: Các bạn hãy bắt đầu bấm giờ (benchmark) từ lúc gõ `yes` ở bước này nhé!*

---

## Phần 4: Kiểm tra AI Endpoint (Inference)

Khi lệnh `terraform apply` chạy xong, bạn sẽ thấy Outputs cung cấp thông tin về Load Balancer:
```text
Outputs:

bastion_public_ip = "20.x.x.x"
endpoint_url = "http://20.x.x.x/v1/completions"
gpu_private_ip = "10.0.2.x"
lb_public_ip = "20.x.x.x"
ssh_command = "ssh azureuser@20.x.x.x"
```

**Quan trọng:** Mặc dù Terraform báo tạo xong hạ tầng, GPU Node bên trong vẫn đang chạy script tải Docker image (vLLM) và model weights (~vài GB) từ Hugging Face. **Bạn cần đợi thêm khoảng 5-10 phút** để model được nạp hoàn toàn vào VRAM của GPU.

### Bước 4.1: Gọi API bằng cURL
Sử dụng IP của Load Balancer để thực hiện truy vấn AI:
```bash
curl -X POST http://<THAY_BẰNG_LB_PUBLIC_IP_CỦA_BẠN>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-4-E2B-it",
    "messages": [
      {"role": "system", "content": "Bạn là một chuyên gia về Microsoft Azure."},
      {"role": "user", "content": "Hãy giải thích ngắn gọn NAT Gateway trong Azure là gì?"}
    ],
    "max_tokens": 150
  }'
```
Nếu nhận được câu trả lời từ AI, chúc mừng bạn đã triển khai thành công AI Endpoint trên Azure! Ghi lại tổng thời gian (Cold start time) từ lúc chạy `terraform apply` đến lúc lệnh `curl` thành công.

### Bước 4.2: SSH vào GPU Node qua Bastion (Dùng để Debug - Tùy chọn)
Nếu gặp lỗi và cần kiểm tra log của vLLM, bạn có thể SSH qua Bastion Host:
```bash
# SSH vào Bastion Host
ssh azureuser@<BASTION_PUBLIC_IP>

# Từ Bastion, SSH vào GPU Node
ssh azureuser@<GPU_PRIVATE_IP>

# Xem log của Docker
sudo docker logs -f vllm
```

---

## Phần 5: Tiêu chí nộp bài (Deliverables)

Để hoàn thành Lab 16 trên môi trường Azure, bạn cần nộp các kết quả sau:
1. **Ảnh chụp màn hình (Screenshot) API gọi thành công:** Chụp lại Terminal chứa lệnh `curl` và kết quả trả về từ mô hình Gemma.
2. **Ảnh chụp màn hình Cost Management:**
   - Truy cập [Azure Portal](https://portal.azure.com/) -> tìm **Cost Management**.
   - Chọn **Cost analysis** -> lọc theo Resource Group vừa tạo.
   - Chụp lại màn hình thể hiện các dịch vụ đang phát sinh chi phí (Virtual Machines, Load Balancer, NAT Gateway).
3. **Report Cold Start Time:** Cung cấp thông số thời gian triển khai từ lúc khởi tạo đến lúc inference thành công (Mục tiêu: < 15 phút cho GPU T4).
4. **Mã nguồn:** Nén file cấu hình thư mục Terraform Azure của bạn và đính kèm.

---

## Phần 6: Dọn dẹp tài nguyên (CỰC KỲ QUAN TRỌNG)

Máy chủ chứa GPU (`Standard_NC4as_T4_v3`), NAT Gateway và Public IP trên Azure sẽ bị trừ tiền liên tục theo giờ. Ngay sau khi test thành công và chụp màn hình nộp bài, bạn **BẮT BUỘC** phải xóa toàn bộ tài nguyên:

**Cách 1: Dùng Terraform (Khuyến nghị)**
```bash
cd terraform-azure
terraform destroy
```
Gõ `yes` để xác nhận việc xóa.

**Cách 2: Dùng Azure Portal**
1. Đăng nhập [Azure Portal](https://portal.azure.com/).
2. Tìm **Resource Groups** -> chọn Resource Group vừa tạo (có tên dạng `ai-lab-rg-xxxx`).
3. Nhấn **Delete Resource Group** -> nhập tên Resource Group để xác nhận -> nhấn **Delete**.

**Cách 3: Dùng Azure CLI (nhanh nhất)**
```bash
# Liệt kê tất cả Resource Groups
az group list --query "[?starts_with(name, 'ai-lab-rg')]" --output table

# Xóa Resource Group (thay tên chính xác)
az group delete --name "ai-lab-rg-xxxxxxxx" --yes --no-wait

# Kiểm tra đã xóa chưa
az group list --query "[?starts_with(name, 'ai-lab-rg')]" --output table
```

> **⚠️ QUAN TRỌNG:** Sau khi xóa Resource Group, hãy kiểm tra lại trong **Subscriptions** -> **Resources** để đảm bảo không còn tài nguyên nào đang chạy. Đặc biệt lưu ý với NAT Gateway và Public IP - hai dịch vụ này tính phí ngay cả khi không có VM nào sử dụng.

---

## Phần 7: Phương án Dự phòng — CPU Instance với LightGBM (Khi không xin được Quota GPU)

> **Ghi chú (tiếng Việt):** Đây là phương án dành cho các bạn dùng tài khoản Azure mới hoặc Free Trial ($200 credit). Azure mặc định hạn chế quota GPU cho các Subscription mới và quá trình xét duyệt tăng quota đôi khi bị từ chối. Thay vì bỏ qua bài lab, bạn sẽ chuyển sang triển khai một **bài toán Machine Learning thực tế** (LightGBM — gradient boosting) trên một **instance CPU cao cấp**. Quy trình này vẫn đầy đủ: Terraform IaC → Cloud VM → Training → Inference → Billing check, chỉ khác là không cần GPU.

### 7.1: Thay đổi cấu hình Terraform sang CPU Instance

**Bước 1 — Thiết lập biến môi trường để đổi VM Size:**

```bash
# Windows (PowerShell)
$env:TF_VAR_vm_size="Standard_D8s_v3"
$env:TF_VAR_hf_token="dummy"

# Linux/Mac
export TF_VAR_vm_size="Standard_D8s_v3"
export TF_VAR_hf_token="dummy"
```

**Bước 2 — Thay đổi source_image_reference trong `terraform-azure/main.tf`:**

Tìm và thay block `source_image_reference` của GPU Node (khoảng dòng 150):

```hcl
# Trước (GPU):
source_image_reference {
  publisher = "nvidia"
  offer     = "gpu-cloud-init"
  sku       = "nvidia-t4-pytorch-2204"
  version   = "latest"
}

# Sau (CPU):
source_image_reference {
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts"
  version   = "latest"
}
```

> **Tại sao `Standard_D8s_v3`?** VM này có 8 vCPU và 32 GB RAM, không yêu cầu quota đặc biệt, có sẵn ngay trên tài khoản mới. Chi phí ~$0.384/giờ tại East US — rẻ hơn đáng kể so với VM GPU (~$3.06/giờ cho `Standard_NC4as_T4_v3`).

### 7.2: Triển khai hạ tầng CPU

```bash
cd terraform-azure
terraform init
terraform apply
```

Gõ `yes` khi được hỏi. Hạ tầng Azure (VNet, NAT, Load Balancer) tạo thường **< 5 phút**.

### 7.3: Kết nối vào CPU Instance qua Bastion

Sau khi `terraform apply` hoàn tất, kết nối vào VM:
```bash
# Lấy IP Bastion từ output
ssh azureuser@<BASTION_PUBLIC_IP>

# Từ Bastion, kết nối vào CPU Node
ssh azureuser@<CPU_PRIVATE_IP>
```

### 7.4: Cài đặt môi trường ML

Trên CPU Node, chạy các lệnh sau:
```bash
# Cập nhật và cài Python packages
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv

python3 -m pip install --upgrade pip
pip3 install lightgbm scikit-learn pandas numpy kaggle

# Tạo thư mục làm việc
mkdir -p ~/ml-benchmark && cd ~/ml-benchmark
```

### 7.5: Tải Dataset từ Kaggle

Chúng ta sẽ dùng **Credit Card Fraud Detection** — bộ dữ liệu chuẩn cho benchmark ML với 284,807 giao dịch thực.

**Lấy Kaggle API Key:**
1. Đăng nhập [kaggle.com](https://www.kaggle.com) -> **Settings** -> **API** -> **Create New Token** -> tải về `kaggle.json`.
2. Copy nội dung vào VM:

```bash
mkdir -p ~/.kaggle
# Tạo file credentials (thay YOUR_USERNAME và YOUR_KEY):
cat > ~/.kaggle/kaggle.json << 'EOF'
{"username": "YOUR_KAGGLE_USERNAME", "key": "YOUR_KAGGLE_API_KEY"}
EOF
chmod 600 ~/.kaggle/kaggle.json

# Tải dataset
kaggle datasets download -d mlg-ulb/creditcardfraud --unzip -p ~/ml-benchmark/
```

### 7.6: Kết quả Benchmark trên `Standard_D8s_v3`

| Metric | Kết quả |
|---|---|
| Thời gian load data | |
| Thời gian training | |
| Best iteration | |
| AUC-ROC | |
| Accuracy | |
| F1-Score | |
| Precision | |
| Recall | |
| Inference latency (1 row) | |
| Inference throughput (1000 rows) | |

### 7.7: Kiểm tra Chi phí sau 1 giờ

Sau khi chạy benchmark xong, **đợi tổng cộng 1 giờ** kể từ lúc `terraform apply` hoàn tất rồi kiểm tra chi phí:

**Cách 1: Dùng Azure Portal**
1. Đăng nhập [Azure Portal](https://portal.azure.com/).
2. Tìm **Cost Management** -> chọn **Cost analysis**.
3. Lọc theo Resource Group vừa tạo, chọn khoảng thời gian hôm nay.
4. Chụp màn hình thể hiện các dịch vụ đang phát sinh chi phí.

**Cách 2: Dùng Azure CLI**
```bash
# Xem chi phí theo Resource Group (cần cài extension cost management)
az extension add --name costmanagement

# Hoặc kiểm tra nhanh bằng cách xem danh sách VM đang chạy
az vm list --resource-group "ai-lab-rg-xxxxxxxx" --query "[?powerState=='VM running'].{Name:name, Size:hardwareProfile.vmSize, State:powerState}" --output table
```

**Ước tính chi phí 1 giờ (East US):**

| Dịch vụ | Loại tài nguyên | Chi phí/giờ |
|---|---|---|
| Virtual Machines — CPU Node | `Standard_D8s_v3` | ~$0.384 |
| Virtual Machines — Bastion | `Standard_B2s` | ~$0.041 |
| NAT Gateway | (xử lý egress traffic) | ~$0.045 + data |
| Load Balancer | Standard (rules) | ~$0.016 |
| Public IPs | (3 IPs) | ~$0.012 |
| **Tổng ước tính** | | **~$0.50/giờ** |

> **Ghi chú (tiếng Việt):** So sánh với GPU: VM `Standard_NC4as_T4_v3` trên Azure có giá ~$3.06/giờ — đắt gấp 6 lần so với CPU. Phương án CPU `Standard_D8s_v3` (~$0.50/giờ) thực tế **rẻ hơn rất nhiều** và có thể dùng ngay mà không cần chờ quota GPU. Đây là bài học thực tế về việc lựa chọn infrastructure phù hợp với workload.

### 7.8: Tiêu chí nộp bài (Phương án CPU thay thế)

Nếu sử dụng phương án CPU + LightGBM, nộp các mục sau (được chấm tương đương phương án GPU):

1. **Screenshot terminal** chạy `python3 benchmark.py` với toàn bộ output kết quả.
2. **File `benchmark_result.json`** chứa metrics đầy đủ (training time, AUC, inference latency).
3. **Screenshot Azure Cost Management** sau 1 giờ triển khai, thể hiện Virtual Machines và NAT Gateway.
4. **Mã nguồn** thư mục `terraform-azure/` đã chỉnh sửa (với `Standard_D8s_v3`, Ubuntu image).
5. **Báo cáo ngắn** (5–10 dòng): so sánh kết quả training time, AUC, inference speed; giải thích lý do phải dùng CPU thay GPU.

---

> **Lưu ý cuối (tiếng Việt):** Dù chạy GPU hay CPU, **bước dọn dẹp (Phần 6 — `terraform destroy` hoặc xóa Resource Group trên Portal) là bắt buộc** ngay sau khi nộp bài. VM `Standard_NC4as_T4_v3` hoặc `Standard_D8s_v3`, NAT Gateway và Public IP vẫn tính phí liên tục theo giờ dù không có tác vụ nào đang chạy. Đừng bỏ qua bước này!

---

## Phụ lục: Azure CLI Quick Reference

Tổng hợp các lệnh CLI thường dùng cho lab này:

```bash
# === AUTH ===
az login                                            # Đăng nhập
az account list --output table                      # Xem danh sách Subscription
az account set --subscription "<SUBSCRIPTION_ID>"   # Chọn Subscription

# === SERVICE PRINCIPAL ===
az ad sp create-for-rbac --name "ai-lab-terraform" --role "Contributor" --scopes "/subscriptions/<SUB_ID>"

# === QUOTA ===
az vm list-usage --location eastus --query "[?name.value=='standardNCSv3Family']" --output table

# === RESOURCE GROUP ===
az group list --query "[?starts_with(name, 'ai-lab-rg')]" --output table
az group delete --name "ai-lab-rg-xxxxxxxx" --yes --no-wait

# === VM STATUS ===
az vm list --resource-group "ai-lab-rg-xxxxxxxx" --query "[].{Name:name, Size:hardwareProfile.vmSize, State:powerState}" --output table

# === SSH ===
ssh azureuser@<BASTION_PUBLIC_IP>
ssh azureuser@<GPU_PRIVATE_IP>  # từ Bastion
```
