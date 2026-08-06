# Tổng quan CPU HE demo

```mermaid
flowchart LR
    A[CSV: salary + KPI mỗi dòng] --> B[Initialize]
    B --> P[(PostgreSQL)]
    P --> C[Reference: SUM salary]
    C --> P
    P --> D[Verify SUM]
    D --> P
    P --> E[Main: nhân từng salary × KPI rồi SUM]
    E --> P
    P --> F[Verify KPI result]
    F --> P
```

Bài toán chính là `SUM(salary[i] × KPI[i])`: nhân theo từng dòng trước, sau đó
mới SUM. `sum_ciphertext` chỉ là kết quả tham chiếu của salary gốc và không đi
vào phép tính chính.

## PostgreSQL schema

| Table | Nội dung |
|---|---|
| `he_demo_sessions` | Scheme, trạng thái và số salary của mỗi session. |
| `he_demo_results` | Expected/decrypted/error riêng cho salary SUM và `SUM(salary[i] × KPI[i])`. |
| `he_demo_artifacts` | Context, ciphertext, evaluation key và wrapped secret key dạng `bytea`. |
| `he_demo_operations` | Lịch sử initialize, sum, multiply và verify. |
| `he_demo_job_runs` | Mọi lần chạy Job: `RUNNING`, `COMPLETED` hoặc `FAILED` cùng error detail. |

## HE được exposed như thế nào

- PostgreSQL chỉ có Service nội bộ; HE Jobs hiện kết nối qua port-forward trên `node3`.
- SUM/Multiply chỉ đọc context, ciphertext và evaluation key; không nhận plaintext hoặc raw secret key.
- Raw secret key không lưu trong PostgreSQL. Database chỉ lưu key đã được AES-GCM wrap.
- Verify Jobs là trusted Jobs: unwrap key trong `/tmp`, decrypt một kết quả rồi cập nhật `he_demo_results`.
- CPU demo không gọi HTTP `/v1/evaluate` của GPU service.

## Job input và output

| Job | Input | Output |
|---|---|---|
| `schema` | `schema.sql`, DB credential | 5 bảng PostgreSQL |
| `initialize` | CSV `salary,kpi`, scheme, wrapping key | Context, encrypted salary/KPI vectors, evaluation keys, wrapped key, expected values |
| `sum` | Context, salary ciphertext, SUM keys | `sum_ciphertext` tham chiếu; không dùng cho phép tính KPI |
| `verify-sum` | Context, `sum_ciphertext`, wrapped key | Decrypted SUM và error |
| `multiply` | Context, salary/KPI ciphertexts, multiply keys, SUM keys | Nhân từng slot trước, rồi tạo `kpi_result_ciphertext = SUM(salary[i] × KPI[i])` |
| `verify-kpi` | Context, `kpi_result_ciphertext`, wrapped key | Decrypted KPI-adjusted amount, error và trạng thái `VERIFIED` |
