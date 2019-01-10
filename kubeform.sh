#!/bin/bash
set -xeuo pipefail

NODE_IP=$1
KEYSDIR="${HOME}/keys"
K8VERSION="v1.10.5_coreos.0"
NODE_DNS=${2:-}

echo "Enabling iptables"
sudo systemctl enable iptables-restore
sudo cp files/iptables-rules /var/lib/iptables/rules-save
sudo sed -i "s/__PUBLICIP__/${NODE_IP}/g" /var/lib/iptables/rules-save
sudo iptables-restore < /var/lib/iptables/rules-save

echo "setting k8s in ${NODE_IP}"

sudo mkdir -p /etc/flannel/
sudo mkdir -p /etc/kubernetes/cni/net.d
sudo mkdir -p /etc/kubernetes/manifests
sudo mkdir -p /etc/kubernetes/ssl/apiserver
sudo mkdir -p /etc/kubernetes/ssl/kube-dashboard
sudo mkdir -p /etc/kubernetes/ssl/kube-dns
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo mkdir -p /etc/systemd/system/etcd-member.service.d
sudo mkdir -p /etc/systemd/system/flanneld.service.d
sudo mkdir -p /opt/bin/
mkdir -p ${KEYSDIR}

sed "s/__PUBLICIP__/${NODE_IP}/g" files/40-listen-address.conf  > /tmp/40-listen-address.conf 
sudo mv /tmp/40-listen-address.conf  /etc/systemd/system/etcd-member.service.d/40-listen-address.conf

echo "starting etcd..."
sudo systemctl start etcd-member
sudo systemctl enable etcd-member


echo "creating keys in ${KEYSDIR}"
openssl genrsa -out ${KEYSDIR}/ca-key.pem 2048
openssl req -x509 -new -nodes -key ${KEYSDIR}/ca-key.pem -days 10000 -out ${KEYSDIR}/ca.pem -subj "/CN=kube-ca"


sed "s/__PUBLICIP__/${NODE_IP}/g" files/openssl.cnf > ${KEYSDIR}/openssl.cnf
if [ -n "${NODE_DNS}" ]
then
  echo "DNS.5 = ${NODE_DNS}" >> ${KEYSDIR}/openssl.cnf
fi

# APIserver
openssl genrsa -out  ${KEYSDIR}/apiserver-key.pem 2048
openssl req -new -key  ${KEYSDIR}/apiserver-key.pem -out  ${KEYSDIR}/apiserver.csr -subj "/CN=kube-apiserver" -config ${KEYSDIR}/openssl.cnf
openssl x509 -req -in  ${KEYSDIR}/apiserver.csr -CA  ${KEYSDIR}/ca.pem -CAkey  ${KEYSDIR}/ca-key.pem -CAcreateserial -out  ${KEYSDIR}/apiserver.pem -days 365 -extensions v3_req -extfile  ${KEYSDIR}/openssl.cnf 
# kubectl
openssl genrsa -out ${KEYSDIR}/admin-key.pem 2048
openssl req -new -key ${KEYSDIR}/admin-key.pem -out ${KEYSDIR}/admin.csr -subj "/CN=kube-admin"
openssl x509 -req -in ${KEYSDIR}/admin.csr -CA ${KEYSDIR}/ca.pem -CAkey ${KEYSDIR}/ca-key.pem -CAcreateserial -out ${KEYSDIR}/admin.pem -days 365
# kube-dns
openssl genrsa -out ${KEYSDIR}/kube-dns-key.pem 2048
openssl req -new -key ${KEYSDIR}/kube-dns-key.pem -out ${KEYSDIR}/kube-dns.csr -subj "/CN=kube-dns"
openssl x509 -req -in ${KEYSDIR}/kube-dns.csr -CA ${KEYSDIR}/ca.pem -CAkey ${KEYSDIR}/ca-key.pem -CAcreateserial -out ${KEYSDIR}/kube-dns.pem -days 365

# kube-dashboard
openssl genrsa -out ${KEYSDIR}/kube-dashboard-key.pem 2048
openssl req -new -key ${KEYSDIR}/kube-dashboard-key.pem -out ${KEYSDIR}/kube-dashboard.csr -subj "/CN=kube-dashboard"
openssl x509 -req -in ${KEYSDIR}/kube-dashboard.csr -CA ${KEYSDIR}/ca.pem -CAkey ${KEYSDIR}/ca-key.pem -CAcreateserial -out ${KEYSDIR}/kube-dashboard.pem -days 365

# Client Cert for Browser
openssl genrsa -out ${KEYSDIR}/clientcert-key.pem 2048
openssl req -new -key ${KEYSDIR}/clientcert-key.pem -out ${KEYSDIR}/clientcert.csr -subj "/CN=kubecert4browser"
openssl x509 -req -in ${KEYSDIR}/clientcert.csr -CA ${KEYSDIR}/ca.pem -CAkey ${KEYSDIR}/ca-key.pem -CAcreateserial -out ${KEYSDIR}/clientcert.pem
openssl pkcs12 -export -in ${KEYSDIR}/clientcert.pem -inkey ${KEYSDIR}/clientcert-key.pem -out ${KEYSDIR}/clientcert.p12 -passout pass:K8sCert -certfile ${KEYSDIR}/ca.pem

sudo cp -p ${KEYSDIR}/ca.pem /etc/kubernetes/ssl/
for POD in "apiserver" "kube-dns" "kube-dashboard"
do
  sudo cp -p ${KEYSDIR}/${POD}.pem /etc/kubernetes/ssl/${POD}/
  sudo cp -p ${KEYSDIR}/${POD}-key.pem /etc/kubernetes/ssl/${POD}/
  sudo cp -p files/kube.conf /etc/kubernetes/ssl/${POD}/
  sudo sed -i -e "s/__POD__/${POD}/g" /etc/kubernetes/ssl/${POD}/kube.conf
done

sudo find /etc/kubernetes/ssl/ -name '*-key.pem' -exec chown root:root {} \; -exec chmod 600 {} \;

sed "s/__PUBLICIP__/${NODE_IP}/g" files/options.env  > /tmp/options.env
sudo mv /tmp/options.env  /etc/flannel/
sudo cp files/40-ExecStartPre-symlink.conf /etc/systemd/system/flanneld.service.d/
sudo cp files/40-flannel.conf /etc/systemd/system/docker.service.d/40-flannel.conf
sudo cp files/docker_opts_cni.env /etc/kubernetes/cni/docker_opts_cni.env
sudo cp files/10-flannel.conf /etc/kubernetes/cni/net.d/10-flannel.conf

sed "s/__PUBLICIP__/${NODE_IP}/g" files/kubelet.service | sed "s/K8VERSION/${K8VERSION}/g" > /tmp/kubelet.service
sudo mv /tmp/kubelet.service  /etc/systemd/system/

sed "s/__PUBLICIP__/${NODE_IP}/g" files/kube-apiserver.yml > /tmp/kube-apiserver.yml
sudo mv /tmp/kube-apiserver.yml /etc/kubernetes/manifests/

sudo cp files/kube-proxy.yml /etc/kubernetes/manifests/
sudo cp files/kube-controller-manager.yml /etc/kubernetes/manifests/
sudo cp files/kube-scheduler.yml /etc/kubernetes/manifests/
sudo cp files/master-kubeconfig.yml /etc/kubernetes/master-kubeconfig.yml

sudo systemctl daemon-reload

echo "configuring etcd"
curl -s -X PUT -d "value={\"Network\":\"10.2.0.0/16\",\"Backend\":{\"Type\":\"vxlan\"}}" "http://${NODE_IP}:2379/v2/keys/coreos.com/network/config"

echo "Creating basicauth file"
MYPASS=$(openssl rand -hex 24)
MYUSER=$(openssl rand -hex 12)
sudo bash -c "echo ${MYPASS},${MYUSER},1 > /etc/kubernetes/ssl/apiserver/basicauth.pass"

echo "starting kubernetes"
sudo systemctl start kubelet
sudo systemctl enable kubelet

echo "waiting for api server to set up"

set +x
max=10
for (( i=0; i <= ${max}; ++i ))
do
   printf "."
   set +e
   status=$(curl -s -w %{http_code} "http:/127.0.0.1:8080/version")
   set -e
   if [ "${status}" != "000" ]; then
      break
   fi
   echo -n "."
   sleep 30 
done
set -x

echo "install kubectl"
curl -s -O https://storage.googleapis.com/kubernetes-release/release/v1.10.5/bin/linux/amd64/kubectl
sudo mv kubectl /opt/bin
sudo chmod +x /opt/bin/kubectl

kubectl config set-cluster default-cluster --server=https://${NODE_IP}:6443 --certificate-authority=${KEYSDIR}/ca.pem 

kubectl config set-credentials default-admin --certificate-authority=${KEYSDIR}/ca.pem --client-key=${KEYSDIR}/admin-key.pem --client-certificate=${KEYSDIR}/admin.pem 

kubectl config set-context default-system --cluster=default-cluster --user=default-admin
kubectl config use-context default-system
kubectl patch node ${NODE_IP} -p "{\"spec\":{\"unschedulable\":false}}"
kubectl create -f files/kube-dns.yml
kubectl create -f files/kube-dashboard.yml
kubectl get pods --all-namespaces
set +x
echo -e "\n=== Basic Auth Credentials ==="
echo "User: ${MYUSER}"
echo "Pass: ${MYPASS}"
echo "You can change those in /etc/kubernetes/ssl/apiserver/basicauth.pass. APIserver restart is required afterwards."
echo "The client certificate for the browser is: ${KEYSDIR}/clientcert.p12"
echo "Import password is 'K8sCert'."
echo -e "=============================\n"
