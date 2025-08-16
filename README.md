## Secure stack (SSH/Webmin/Fail2ban/UFW)

คำสั่งชุดนี้จะช่วยติดตั้งและตั้งค่าระบบความปลอดภัยพื้นฐานบนเซิร์ฟเวอร์ Debian เช่น SSH, Webmin, Fail2ban และ UFW (firewall) โดยอัตโนมัติ  

curl -fsSL https://raw.githubusercontent.com/peawza/setup_debian/main/secure-stack.sh -o secure-stack.sh
chmod +x secure-stack.sh
sudo ./secure-stack.sh



## stack (Minikube)

คำสั่งชุดนี้จะช่วยติดตั้ง Minikube สำหรับการจำลอง Kubernetes cluster บนเครื่อง  

curl -fsSL https://raw.githubusercontent.com/peawza/setup_debian/main/kube-stack.sh -o kube-stack.sh
chmod +x kube-stack.sh
sudo ./kube-stack.sh

