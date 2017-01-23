# k8single

Basic k8s setup for a Core OS single node with the aim to use for staging or CI deployments. Follows https://coreos.com/kubernetes/docs/latest/getting-started.html

This version has been tested with Container Linux installed on KVM VPS. It requires a Core OS instance running, then connect to it and:

```bash
git clone https://github.com/m3adow/k8single/; 
cd k8single
./kubeform.sh [myip-address] [DNS entry for K8s apiserver (optional)]
```

This will deploy k8 into a single schedulable node, it sets up kubectl in the node and deploys the skydns and dashboard add ons. Furthermore iptables is set up to secure etcd2.
Additionally it'll create a random user and a random password for direct access to the dashboard as well as a client certificate for easier access.

It also includes a busybox node file that can be deployed by:
```bash
kubectl create -f files/busybox
```

This might come useful to debug issues with the set up. To execute commands in busybox run:
```bash
kubectl exec busybox -- [command]
```
