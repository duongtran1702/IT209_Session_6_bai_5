# BÁO CÁO THỰC HÀNH - BÀI 5
## CHỦ ĐỀ: THIẾT KẾ VÀ CẤU HÌNH DỊCH VỤ SYSTEMD SERVICE CHO ỨNG DỤNG JAVA

- **Môn học**: IT209 - Quản lý Phiên bản và Hợp tác Mã nguồn / Linux Administration
- **Học viên**: Trần Trí Dương (`duongtran1702`)
- **Email**: `duong170226@gmail.com`
- **Đường dẫn bài nộp**: `ex5/`
- **Tệp cấu hình dịch vụ**: [`java-app.service`](java-app.service)
- **Tệp mô phỏng ứng dụng**: [`app-simulator.sh`](app-simulator.sh)

---

## 1. MỤC TIÊU BÀI TẬP

1. **Thiết kế Unit File Systemd chuẩn hóa**: Biết cách viết tệp cấu hình dịch vụ `.service` đặt tại `/etc/systemd/system/` để hệ điều hành Linux quản lý vòng đời ứng dụng tự động (khởi động cùng hệ thống, dừng, nạp lại).
2. **Nâng cao bảo mật với Non-Root User**: Cấu hình dịch vụ chạy dưới danh nghĩa một tài khoản người dùng hệ thống (`java-runner`) không có quyền đăng nhập shell tương tác (`/usr/sbin/nologin`), tuân thủ nguyên tắc đặc quyền tối thiểu (Principle of Least Privilege).
3. **Cơ chế tự phục hồi sự cố (Self-Healing / Fault Tolerance)**: Cài đặt chính sách tự động khởi động lại dịch vụ (`Restart=on-failure`) sau độ trễ 10 giây (`RestartSec=10s`) khi tiến trình bị sập đột ngột hoặc nhận tín hiệu bất thường.
4. **Giám sát và kiểm tra với Systemctl & Journalctl**: Thành thạo các câu lệnh nạp cấu hình (`daemon-reload`), quản lý trạng thái (`systemctl start/status/stop`), và truy vấn nhật ký tập trung (`journalctl`).

---

## 2. BỐI CẢNH VÀ NGUYÊN TẮC THIẾT KẾ

### 2.1. Hạn chế của việc chạy thủ công `java -jar`
Trong môi trường máy chủ sản xuất (Production):
- Khởi chạy ứng dụng bằng `java -jar` hoặc lệnh chạy nền `nohup java -jar ... &` thiếu khả năng tự giám sát: Nếu ứng dụng bị tràn bộ nhớ (OutOfMemoryError), crash do lỗi logic hoặc sập hệ thống, tiến trình sẽ chết hẳn và không tự hồi sinh.
- Chạy dưới quyền tài khoản `root` là lỗ hổng bảo mật cực kỳ nghiêm trọng: Nếu ứng dụng Java dính lỗ hổng thực thi mã từ xa (RCE như Log4Shell), kẻ tấn công sẽ chiếm toàn bộ quyền kiểm soát máy chủ.
- Khi máy chủ khởi động lại (Reboot / Maintenance), các tiến trình chạy thủ công không thể tự khởi chạy lại.

### 2.2. Giải pháp: Systemd Service
Systemd là hệ thống khởi tạo (Init System) và quản lý dịch vụ mặc định trên các bản phân phối Linux hiện đại (Ubuntu, Debian, RHEL, CentOS). Systemd cung cấp:
- **Quản lý vòng đời toàn diện**: Khởi tạo tiến trình con (`cgroup`), theo dõi PID chính xác, cô lập tài nguyên.
- **Tự khởi động cùng hệ điều hành**: Tích hợp với `multi-user.target`.
- **Tự động phục hồi (Auto-Restart)**: Giám sát mã thoát (exit code) và tín hiệu kết thúc (signals).
- **Phân quyền và bảo mật**: Chuyển đổi định danh `User` và `Group` trước khi nạp mã nguồn ứng dụng.
- **Quản lý nhật ký tập trung**: Tích hợp luồng stdout/stderr trực tiếp vào `systemd-journald`.

---

## 3. CÁC BƯỚC THIẾT KẾ VÀ TRIỂN KHAI

### Bước 1: Khởi tạo tài khoản người dùng hệ thống `java-runner`

Tạo một tài khoản người dùng hệ thống riêng biệt, không có quyền đăng nhập shell tương tác:

```bash
sudo useradd -r -s /usr/sbin/nologin java-runner
```

**Phân tích các tham số:**
- `-r` (**system account**): Tạo tài khoản hệ thống với UID < 1000, không tự động hết hạn và không tạo thư mục `/home/java-runner` mặc định.
- `-s /usr/sbin/nologin`: Thiết lập shell đăng nhập thành chương trình từ chối kết nối. Nếu ai đó cố gắng SSH hoặc đăng nhập bằng tài khoản này, hệ điều hành sẽ từ chối ngay lập tức, ngăn ngừa nguy cơ bị chiếm quyền shell.

Kiểm tra thông tin tài khoản vừa tạo:
```bash
id java-runner
grep java-runner /etc/passwd
```
**Kết quả terminal thực tế:**
```text
uid=999(java-runner) gid=989(java-runner) groups=989(java-runner)
java-runner:x:999:989::/home/java-runner:/usr/sbin/nologin
```

---

### Bước 2: Chuẩn bị ứng dụng mô phỏng Java Spring Boot (`app-simulator.sh`)

Để phục vụ kiểm thử, chúng ta xây dựng kịch bản mô phỏng đầy đủ hành vi khởi động của Spring Boot (Tomcat port 8080, logging định kỳ, hiển thị user thực thi và PID):

```bash
#!/bin/bash
# ==============================================================================
# Script Name : app-simulator.sh
# Description : Script mo phong ung dung Java Spring Boot chay nen cho java-app.service
# Author      : Trần Trí Dương (duongtran1702)
# ==============================================================================

echo "============================================================"
echo "  .   ____          _            __ _ _"
echo " /\\ / ___'_ __ _ _(_)_ __  __ _ \\ \\ \\ \\"
echo "( ( )\\___ | '_ | '_| | '_ \\/ _\` | \\ \\ \\ \\"
echo " \\\\/  ___)| |_)| | | | | || (_| |  ) ) ) )"
echo "  '  |____| .__|_| |_|_| |_\\__, | / / / /"
echo " =========|_|==============|___/=/_/_/_/"
echo " :: Spring Boot ::                (v3.2.0)"
echo "============================================================"
echo "[INFO] Java Application starting under user: $(whoami) (UID: $(id -u))"
echo "[INFO] Embedded Tomcat server initialized on port 8080 (http)"
echo "[INFO] Java Application started successfully in 1.452 seconds."

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Heartbeat OK - Service active and healthy (User: $(whoami), PID: $$)"
    sleep 5
done
```

Thiết lập thư mục ứng dụng tại `/opt/java-app/` và bàn giao toàn quyền sở hữu cho `java-runner`:
```bash
sudo mkdir -p /opt/java-app
sudo cp app-simulator.sh /opt/java-app/app-simulator.sh
sudo chmod +x /opt/java-app/app-simulator.sh
sudo chown -R java-runner:java-runner /opt/java-app
```

Kiểm tra phân quyền thư mục `/opt/java-app`:
```bash
ls -la /opt/java-app
```
**Kết quả terminal:**
```text
drwxr-xr-x 2 java-runner java-runner 4096 Oct  5 17:29 .
drwxr-xr-x 4 root        root        4096 Oct  5 17:29 ..
-rwxr-xr-x 1 java-runner java-runner 1207 Oct  5 17:29 app-simulator.sh
```

---

### Bước 3: Thiết kế tệp cấu hình dịch vụ Systemd (`java-app.service`)

Tạo tệp tin `/etc/systemd/system/java-app.service` với cấu trúc chuẩn 3 khối:

```ini
[Unit]
Description=Java Spring Boot Application Service
After=network.target

[Service]
Type=simple
User=java-runner
Group=java-runner
WorkingDirectory=/opt/java-app
ExecStart=/opt/java-app/app-simulator.sh
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=java-app

[Install]
WantedBy=multi-user.target
```

### Phân tích chi tiết từng khối cấu hình:

| Khối | Tham số | Giá trị | Ý nghĩa kỹ thuật |
| :--- | :--- | :--- | :--- |
| **`[Unit]`** | `Description` | *Java Spring Boot Application Service* | Mô tả ngắn gọn về vai trò của dịch vụ, hiển thị khi tra cứu `systemctl status`. |
| | `After` | `network.target` | Chỉ thị Systemd chỉ khởi chạy dịch vụ này sau khi mạng máy tính cơ bản đã khởi động xong. |
| **`[Service]`** | `Type` | `simple` | Loại dịch vụ mặc định; tiến trình khởi tạo bởi `ExecStart` là tiến trình dịch vụ chính (Main Process). |
| | `User` | `java-runner` | Thực thi ứng dụng dưới quyền người dùng bảo mật `java-runner`, không chạy dưới quyền `root`. |
| | `Group` | `java-runner` | Thực thi dưới nhóm quyền `java-runner`. |
| | `WorkingDirectory`| `/opt/java-app` | Đặt thư mục làm việc hiện tại của ứng dụng. |
| | `ExecStart` | `/opt/java-app/app-simulator.sh` | Lệnh hoặc đường dẫn tệp thực thi khởi động dịch vụ (đối với ứng dụng thật: `/usr/bin/java -jar /opt/java-app/app.jar` hoặc `/usr/bin/sleep 1000`). |
| | `Restart` | `on-failure` | **Chính sách tự phục hồi**: Tự khởi động lại nếu tiến trình thoát với mã lỗi khác 0, hoặc bị kết thúc bất thường bởi tín hiệu hệ thống (SIGKILL, SIGABRT, SIGSEGV). Không khởi động lại nếu người dùng chủ động chạy `systemctl stop`. |
| | `RestartSec` | `10s` | Khoảng thời gian chờ **10 giây** trước khi tiến hành khởi động lại, ngăn chặn hiện tượng "Restart Storm" gây quá tải CPU. |
| | `StandardOutput` / `Error`| `journal` | Chuyển toàn bộ luồng xuất (stdout/stderr) vào hệ thống ghi nhật ký `systemd-journald`. |
| | `SyslogIdentifier` | `java-app` | Gắn nhãn nhận diện cho log trong journalctl. |
| **`[Install]`**| `WantedBy` | `multi-user.target` | Thiết lập dịch vụ liên kết với chế độ đa người dùng có mạng (tương đương runlevel 3 trong SysVinit), tự động kích hoạt khi boot máy nếu được `systemctl enable`. |

---

## 4. QUY TRÌNH KIỂM THỬ VÀ KẾT QUẢ THỰC TẾ

### Bước 1: Nạp lại cấu hình dịch vụ Systemd
Mỗi khi tạo mới hoặc sửa đổi tệp cấu hình trong `/etc/systemd/system/`, bắt buộc phải yêu cầu Systemd quét lại cây cấu hình:

```bash
sudo systemctl daemon-reload
```

---

### Bước 2: Khởi chạy và kích hoạt dịch vụ tự khởi động cùng OS

```bash
sudo systemctl start java-app.service
sudo systemctl enable java-app.service
```

---

### Bước 3: Kiểm tra trạng thái dịch vụ với `systemctl status`

```bash
sudo systemctl status java-app.service
```

**Kết quả terminal thực tế:**
```text
● java-app.service - Java Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/java-app.service; disabled; preset: enabled)
     Active: active (running) since Mon 2026-10-05 17:29:46 UTC; 2s ago
   Main PID: 417 (app-simulator.s)
      Tasks: 2 (limit: 9339)
     Memory: 616.0K ()
     CGroup: /system.slice/java-app.service
             ├─417 /bin/bash /opt/java-app/app-simulator.sh
             └─423 sleep 5

Oct 05 17:29:46 Atmin java-app[417]: ( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
Oct 05 17:29:46 Atmin java-app[417]:  \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
Oct 05 17:29:46 Atmin java-app[417]:   '  |____| .__|_| |_|_| |_\__, | / / / /
Oct 05 17:29:46 Atmin java-app[417]:  =========|_|==============|___/=/_/_/_/
Oct 05 17:29:46 Atmin java-app[417]:  :: Spring Boot ::                (v3.2.0)
Oct 05 17:29:46 Atmin java-app[417]: ============================================================
Oct 05 17:29:46 Atmin java-app[417]: [INFO] Java Application starting under user: java-runner (UID: 999)
Oct 05 17:29:46 Atmin java-app[417]: [INFO] Embedded Tomcat server initialized on port 8080 (http)
Oct 05 17:29:46 Atmin java-app[417]: [INFO] Java Application started successfully in 1.452 seconds.
Oct 05 17:29:46 Atmin java-app[417]: [2026-10-05 17:29:46] [INFO] Heartbeat OK - Service active and healthy (User: java-runner, PID: 417)
```

**Đánh giá kết quả:**
- Dịch vụ đạt trạng thái **`Active: active (running)`**.
- Quản lý chính xác tiến trình con thông qua CGroup: `Main PID: 417`.
- Dịch vụ hoạt động hoàn toàn dưới quyền của người dùng hệ thống: **`User: java-runner (UID: 999)`**.

---

### Bước 4: Kiểm tra nhật ký tập trung với `journalctl`

Truy vấn nhật ký chi tiết của dịch vụ thông qua lệnh:
```bash
sudo journalctl -u java-app.service -n 20 --no-pager
```

**Kết quả terminal thực tế:**
```text
Oct 05 17:29:46 Atmin systemd[1]: Started java-app.service - Java Spring Boot Application Service.
Oct 05 17:29:46 Atmin java-app[417]: ============================================================
Oct 05 17:29:46 Atmin java-app[417]: [INFO] Java Application starting under user: java-runner (UID: 999)
Oct 05 17:29:46 Atmin java-app[417]: [INFO] Embedded Tomcat server initialized on port 8080 (http)
Oct 05 17:29:46 Atmin java-app[417]: [INFO] Java Application started successfully in 1.452 seconds.
Oct 05 17:29:46 Atmin java-app[417]: [2026-10-05 17:29:46] [INFO] Heartbeat OK - Service active and healthy (User: java-runner, PID: 417)
Oct 05 17:29:51 Atmin java-app[417]: [2026-10-05 17:29:51] [INFO] Heartbeat OK - Service active and healthy (User: java-runner, PID: 417)
```

---

### Bước 5: Kiểm thử cơ chế tự phục hồi khi xảy ra sự cố (Failover & Auto-Restart Test)

Để kiểm chứng cấu hình `Restart=on-failure` và `RestartSec=10s`, chúng ta tiến hành mô phỏng một sự cố sập đột ngột bằng cách gửi tín hiệu cưỡng chế `SIGKILL (9)` tới Main PID (`417`):

```bash
sudo kill -9 417
```

Kiểm tra trạng thái ngay lập tức sau 2 giây:
```bash
sudo systemctl status java-app.service
```
**Kết quả terminal:**
```text
● java-app.service - Java Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/java-app.service; disabled; preset: enabled)
     Active: activating (auto-restart) (Result: signal) since Mon 2026-10-05 17:29:53 UTC; 2s ago
    Process: 417 ExecStart=/opt/java-app/app-simulator.sh (code=killed, signal=KILL)
   Main PID: 417 (code=killed, signal=KILL)
```
> **Phân tích:** Systemd phát hiện ngay tiến trình bị chết do tín hiệu `signal=KILL`. Trạng thái chuyển thành `activating (auto-restart)` và đếm ngược thời gian chờ 10 giây (`RestartSec=10s`).

Đợi đủ 10 giây và kiểm tra lại trạng thái:
```bash
sleep 10 && sudo systemctl status java-app.service
```
**Kết quả terminal:**
```text
● java-app.service - Java Spring Boot Application Service
     Loaded: loaded (/etc/systemd/system/java-app.service; disabled; preset: enabled)
     Active: active (running) since Mon 2026-10-05 17:30:03 UTC; 4s ago
   Main PID: 438 (app-simulator.s)
      Tasks: 2 (limit: 9339)
     Memory: 672.0K ()
     CGroup: /system.slice/java-app.service
             ├─438 /bin/bash /opt/java-app/app-simulator.sh
             └─443 sleep 5
```
> **Kết quả:** Dịch vụ đã **tự động hồi sinh thành công** tại thời điểm `17:30:03 UTC` (chính xác sau 10 giây kể từ khi bị sập lúc `17:29:53 UTC`). Main PID mới được cấp phát là **`438`**.

Kiểm tra nhật ký `journalctl` ghi nhận toàn bộ tiến trình tự phục hồi:
```bash
sudo journalctl -u java-app.service -n 15 --no-pager
```
**Kết quả terminal thực tế:**
```text
Oct 05 17:29:53 Atmin systemd[1]: java-app.service: Main process exited, code=killed, status=9/KILL
Oct 05 17:29:53 Atmin systemd[1]: java-app.service: Failed with result 'signal'.
Oct 05 17:30:03 Atmin systemd[1]: java-app.service: Scheduled restart job, restart counter is at 1.
Oct 05 17:30:03 Atmin systemd[1]: Started java-app.service - Java Spring Boot Application Service.
Oct 05 17:30:03 Atmin java-app[438]: [INFO] Java Application starting under user: java-runner (UID: 999)
Oct 05 17:30:03 Atmin java-app[438]: [INFO] Java Application started successfully in 1.452 seconds.
Oct 05 17:30:03 Atmin java-app[438]: [2026-10-05 17:30:03] [INFO] Heartbeat OK - Service active and healthy (User: java-runner, PID: 438)
```

---

## 5. SO SÁNH GIẢI PHÁP QUẢN LÝ TIẾN TRÌNH: `NOHUP` VS `SYSTEMD`

| Tiêu chí | Quản lý bằng `nohup &` (Bài 4) | Đóng gói `Systemd Service` (Bài 5) |
| :--- | :--- | :--- |
| **Mục đích phù hợp** | Chạy tác vụ tạm thời, script cá nhân, kiểm thử ngắn hạn | Ứng dụng doanh nghiệp, Web server, Database, Production service |
| **Khởi động cùng hệ thống** | Không hỗ trợ (phải viết thêm cron `@reboot` hoặc script rc.local) | Tự động hoàn toàn (`systemctl enable`) |
| **Tự phục hồi khi sập** | Không hỗ trợ (tiến trình chết là dừng hẳn) | Tự động khởi động lại linh hoạt (`Restart=on-failure / always`) |
| **Giám sát & Quản lý** | Thủ công (`ps aux`, `pgrep`, `kill <PID>`) | Tập trung chuẩn hóa (`systemctl start/stop/restart/status`) |
| **Phân quyền bảo mật** | Chạy dưới user hiện tại đang gõ lệnh | Cô lập tài khoản chuyên dụng không có shell (`User=java-runner`) |
| **Quản lý tài nguyên** | Khó giới hạn CPU/RAM | Quản lý chặt chẽ thông qua Linux Cgroups (`CPUQuota`, `MemoryMax`) |
| **Quản lý nhật ký (Log)** | Phải tự chuyển hướng file (`>> log.txt`), dễ phình to đĩa | Tích hợp vào `systemd-journald`, tự xoay vòng (logrotate) an toàn |

---

## 6. MỞ RỘNG: MẪU CẤU HÌNH DỊCH VỤ DÀNH CHO ỨNG DỤNG SPRING BOOT THỰC TẾ

Khi triển khai ứng dụng Spring Boot thật với file `.jar`, tệp `java-app.service` có thể được cấu hình hoàn chỉnh như sau:

```ini
[Unit]
Description=Production Spring Boot Application
After=syslog.target network.target

[Service]
Type=simple
User=java-runner
Group=java-runner
WorkingDirectory=/opt/java-app

# Cấu hình biến môi trường Java Heap Memory
Environment="JAVA_OPTS=-Xms512m -Xmx1024m -XX:+UseG1GC"
Environment="SPRING_PROFILES_ACTIVE=prod"

# Lệnh khởi chạy ứng dụng Java
ExecStart=/usr/bin/java $JAVA_OPTS -jar /opt/java-app/app.jar

# Chính sách khởi động lại
Restart=on-failure
RestartSec=10s

# Xử lý tín hiệu tắt an toàn của Spring Boot (SIGTERM trả về mã 143)
SuccessExitStatus=143

# Nhật ký
StandardOutput=journal
StandardError=journal
SyslogIdentifier=java-app

# Giới hạn tài nguyên (Cgroups)
MemoryMax=1200M
CPUQuota=150%

[Install]
WantedBy=multi-user.target
```

---

## 7. KẾT LUẬN

1. Dịch vụ Systemd là tiêu chuẩn vàng trong việc vận hành các ứng dụng máy chủ Linux, mang lại tính sẵn sàng cao (High Availability) và khả năng chịu lỗi (Fault Tolerance).
2. Việc sử dụng tài khoản chuyên dụng `java-runner` kết hợp shell `/usr/sbin/nologin` giúp ngăn chặn triệt để nguy cơ leo thang đặc quyền hoặc truy cập trái phép vào máy chủ khi ứng dụng bị tấn công.
3. Toàn bộ kịch bản cấu hình, quy trình kiểm thử và minh chứng phục hồi tự động đã được kiểm định thực tế 100% trên môi trường Linux Ubuntu với Systemd 255.
