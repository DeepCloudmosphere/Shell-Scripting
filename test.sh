#!/bin/bash

# Aotomate kubernetes setup on vm cluster
# Author: Deepak Verma

# check script is run as root

if [ "$UID" -ne 0 ];then
    echo -e "\033[0;1mYou must  run this script as root switch user by (su -i) and run again! "
    exit 1
fi


####print color####
function print_color(){

 NC='\033[0m'
 case $1 in
    "green") COLOR='\033[0;32m' ;;
    "red") COLOR='\033[0;31m' ;;
    "*") COLOR='\033[0m' ;;
  esac

  echo -e "${COLOR}$2 ${NC}"
}

#######################################
# Check the status of a given service. If not active exit script
# Arguments:
#   Service Name. eg: firewalld, mariadb
#######################################
function check_service_status(){
  service_is_active=$(  systemctl is-active $1)

  if [ $service_is_active = "active" ]
  then
    print_color "green" "\n$1 is active and running\n"
  else
    print_color "green" "\n$1 is not active/running\n"
    exit 1
  fi
}


#######################################
# Check the status of a firewalld rule. If not configured exit.
# Arguments:
#   Port Number. eg: 3306, 80
#######################################
function is_firewalld_rule_configured(){

  firewalld_ports=$(  firewall-cmd --list-all --zone=public | grep ports)

  if [[ $firewalld_ports == *$1* ]]
  then
    print_color "green" "FirewallD has port $1 configured"
  else
    print_color "green" "FirewallD port $1 is not configured"
    exit 1
  fi
}



##### update system ########
print_color green "\n----------------------------------System updating... wait\n"
apt update

print_color green "\n----------------------------------System update complete\n"
print_color green "\n----------------------------------configuring port on Server..."

# Install and configure firewalld
print_color "green" "Installing FirewallD.. "
  apt install -y firewalld

print_color "green" " FirewallD install successfully "

  service firewalld start
  systemctl enable firewalld

# Check FirewallD Service is running
check_service_status firewalld

print_color green "\n------------------------Configure Firewall rules for master node------------------------\n"


print_color green  "\nKubernetes API server port\n"
  firewall-cmd --permanent --zone=public --add-port=6443/tcp
  firewall-cmd --reload
is_firewalld_rule_configured 6443

print_color green "\nEtcd server client API port\n"
  firewall-cmd --permanent --zone=public --add-port=2379-2380/tcp
  firewall-cmd --reload
is_firewalld_rule_configured 2379-2380

print_color green "\nKubelet API Self, Control plane port\n"
  firewall-cmd --permanent --zone=public --add-port=10250/tcp
  firewall-cmd --reload
is_firewalld_rule_configured 10250

print_color green "\nKube-scheduler port\n"
  firewall-cmd --permanent --zone=public --add-port=10259/tcp
  firewall-cmd --reload
is_firewalld_rule_configured 10259

print_color green "\nKube-controller-manager port\n"
  firewall-cmd --permanent --zone=public --add-port=10257/tcp
  firewall-cmd --reload
is_firewalld_rule_configured 10257



print_color green "--------------Docker Installation and configuration start----------------------"

#docker
curl -fsSL https://get.docker.com -o get-docker.sh
  sh ./get-docker.sh

# check service
check_service_status docker
print_color green "--------------Docker Installation complete--------"

print_color green "-------configure docker to use systemd driver---------"
# Setup daemon.
  cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
  systemctl enable docker
  systemctl restart docker

# check service
check_service_status docker

print_color green "-------configure docker successfully-----"


print_color green "-------configure docker runtime interface cri-docker---------"


# cri-docker.io for docker interface

  git clone https://github.com/Mirantis/cri-dockerd.git


  wget https://storage.googleapis.com/golang/getgo/installer_linux
  chmod +x ./installer_linux
  ./installer_linux
  source ~/.bash_profile

  cd cri-dockerd
  mkdir bin
  go build -o bin/cri-dockerd
  mkdir -p /usr/local/bin
  install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
  cp -a packaging/systemd/* /etc/systemd/system
  sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
  systemctl daemon-reload
  systemctl enable --now cri-docker.socket
  systemctl start cri-docker.service
  # systemctl status cri-docker.service

check_service_status cri-docker

print_color green "-------configure cri-docker successfully---------"





print_color green "-------configure and install kubeadm, kubelet, kubectl----------"

  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl

  curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" |   tee /etc/apt/sources.list.d/kubernetes.list


  apt-get update
  apt-get install -y kubelet kubeadm 
  apt-mark hold kubelet kubeadm 


  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

  curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"

  echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

kubectlVersion=$(kubectl version --client -o yaml)
major=$( echo ${kubectlVersion} | grep -i major | cut -d ":" -f 11 | cut -d " " -f 2 | sed 's/"//g' )
minor=$( echo ${kubectlVersion} | grep -i minor | cut -d ":" -f 12 | cut -d " " -f 2 | sed 's/"//g' )
print_color green  "\nYour Kubectl version is :-> ${major}.${minor}"

















kubeadm init --pod-network-cidr 10.244.0.0/16 --apiserver-advertise-address=192.168.56.2 --cri-socket unix:///var/run/cri-dockerd.sock 

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml



