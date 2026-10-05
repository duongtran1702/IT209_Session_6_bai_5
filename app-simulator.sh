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
