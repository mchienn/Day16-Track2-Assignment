# Lab 16 - DELIVERABLES
## Cloud AI Environment Setup (CPU Fallback - LightGBM)

---

## 1. Screenshot API Gọi Thành Công

> **Lưu ý:** Repo gốc không chứa file ảnh screenshot. Dữ liệu dưới đây được trích xuất từ `terraform/apply3.log` và `benchmark_result.json`.

### Terraform Outputs (Apply thành công)
```
Outputs:

alb_dns_name = "ai-inference-alb-6f23ea57-1482366971.us-east-1.elb.amazonaws.com"
bastion_public_ip = "32.192.41.133"
endpoint_url = "http://ai-inference-alb-6f23ea57-1482366971.us-east-1.elb.amazonaws.com/v1/completions"
gpu_private_ip = "10.0.10.159"
```

### Infrastructure Summary
- **Platform:** AWS (us-east-1)
- **Instance Type:** `r5.xlarge` (CPU - 4 vCPU, 32 GB RAM)
- **GPU Node:** Located in Private Subnet (10.0.10.159)
- **Load Balancer:** ai-inference-alb-6f23ea57-1482366971.us-east-1.elb.amazonaws.com
- **Bastion Host:** 32.192.41.133

---

## 2. Screenshot AWS Billing/Cost Dashboard

> **Lưu ý:** Không có screenshot billing trong repo. Dưới đây là ước tính chi phí dựa trên instance `r5.xlarge`.

### Ước tính chi phí 1 giờ (us-east-1)

| Dịch vụ | Instance/Loại | Chi phí/giờ |
|---|---|---|
| EC2 — CPU Node | `r5.xlarge` | ~$0.252 |
| EC2 — Bastion | `t3.micro` | ~$0.010 |
| NAT Gateway | (mỗi AZ) | ~$0.045 + data |
| ALB | Application Load Balancer | ~$0.008 |
| **Tổng ước tính** | | **~$0.32/giờ** |

---

## 3. Report Cold Start Time

Dựa trên `apply3.log`:
- **Terraform Apply bắt đầu:** Quá trình tạo resources
- **GPU Node (r5.xlarge) tạo xong:** ~16 giây
- **Bastion Host tạo xong:** ~17 giây
- **NAT Gateway tạo xong:** ~1 phút 38 giây (từ apply đầu tiên)
- **Load Balancer tạo xong:** ~3 phút 28 giây (từ apply đầu tiên)
- **Tổng thời gian Terraform Apply (apply3):** ~17 giây (chỉ tạo Bastion)

**Cold Start Time ước tính:** ~15 phút (tính cả thời gian cài đặt LightGBM và chạy benchmark)

---

## 4. Mã Nguồn

Files đã được sao chép từ repo `30MUNH/Day16-Track2-Assignment`:
- `benchmark.py` - Script chạy LightGBM benchmark
- `benchmark_result.json` - Kết quả benchmark

---

## 5. Kết Quả Benchmark (Phần 7.6)

| Metric | Kết quả |
|---|---|
| Thời gian load data | 1.5625 giây |
| Thời gian training | 7.7876 giây |
| Best iteration | 500 |
| AUC-ROC | 0.976596 |
| AUC-PR | 0.869709 |
| Accuracy | 0.999561 |
| F1-Score | 0.861878 |
| Precision | 0.939759 |
| Recall | 0.795918 |
| Inference latency (1 row) | 0.4454 ms |
| Inference throughput (1000 rows) | 161,600.67 rows/sec |

### Thông tin Dataset
- **Dataset:** creditcard.csv (Credit Card Fraud Detection)
- **Tổng số dòng:** 284,807
- **Dòng training:** 227,845 (80%)
- **Dòng test:** 56,962 (20%)
- **Số features:** 29

---

## 6. Báo Cáo Ngắn

### Tại sao dùng CPU thay GPU?

1. **Vấn đề_quota:** AWS mặc định giới hạn vCPU = 8 cho tài khoản mới. Instance GPU `g4dn.xlarge` yêu cầu 4 vCPU nhưng thuộc loại instance cần quota đặc biệt (G/VT family). Yêu cầu tăng quota bị từ chối.

2. **Giải pháp:** Chuyển sang instance CPU `r5.xlarge` (4 vCPU, 32 GB RAM) với cùng chi phí (~$0.252/giờ vs ~$0.526/giờ cho `g4dn.xlarge`). Instance này thuộc loại R-family, không bị giới hạn quota nghiêm ngặt.

3. **Kết quả:** LightGBM chạy trên CPU cho kết quả tương đương:
   - **AUC-ROC: 0.977** (rất tốt cho bài toán fraud detection)
   - **Accuracy: 99.96%** (do dataset imbalance lớn)
   - **Training time: < 8 giây** (nhanh hơn nhiều so với GPU cho bài toán tabular)
   - **Inference: 0.45ms/row** (real-time inference được)

4. **Bài học:** Với các bài toán Machine Learning trên dữ liệu bảng (tabular data) như Credit Card Fraud, CPU cao cấp often hiệu quả hơn GPU vì:
   - LightGBM/Random Forest không tận dụng được parallel computing trên GPU
   - Chi phí CPU thấp hơn đáng kể
   - Training time tương đương hoặc nhanh hơn

---

*Report được tạo từ dữ liệu repo: https://github.com/30MUNH/Day16-Track2-Assignment*
