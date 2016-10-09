#!/bin/bash

# Author: Omar Abu Ajamieh

# Purpose: This script is used to create a AWS resources and launch a wordpress application

### script inputs

APP_NAME=$1
ENV=$2
NUM_SERVERS=$3
INS_TYPE=$4
## set the directory that will contain all the git files 
ANSIBLE_FILE_PATH="/opt/infrastructure"
### start by creating the AWS resources

## create the ansible variables file 
echo > $ANSIBLE_FILE_PATH/infra/vars/main.yml
echo $ANSIBLE_FILE_PATH
cat > $ANSIBLE_FILE_PATH/infra/vars/main.yml << EOF
---
IMAGE : ami-d732f0b7
REGION : us-west-2
SEC_GROUP : infra_sec
KEY : infra
ZONE: us-west-2a
APP_NAME: $1
ENV: $2
NUM_SERVERS: $3 
INS_TYPE: $4
EOF

### create the security group, EC2 instances, Load Balancer

ansible-playbook create-ec2-lb-sec.yml -vv
## i will run sleep to make sure that the instances are running 
sleep 200s 
### get instances public IP and add them to inventory file
echo "---"  > $ANSIBLE_FILE_PATH/install-docker.yml 
echo "---"  > $ANSIBLE_FILE_PATH/create-docker-image.yml
echo "[$APP_NAME-$ENV]" > $ANSIBLE_FILE_PATH/hosts
aws ec2 describe-instances --filters Name=tag-value,Values=INFRA-"$APP_NAME"* |grep PublicIp |awk -F ':' '{print $2}' |sed 's/,//g' |sed 's/"//g' |sed 's/ //g' |sort |uniq |while read p ;do

cat >> $ANSIBLE_FILE_PATH/hosts << EOF
$p

EOF
done
### get database ip and add it to the hosts file 
DB_IP=`aws ec2 describe-instances --filters Name=tag-value,Values=INFRA-"$APP_NAME"* |grep PublicIp |awk -F ':' '{print $2}' |sed 's/,//g' |sed 's/"//g' |sed 's/ //g' |sort |uniq |tail -1`
cat >> $ANSIBLE_FILE_PATH/hosts << EOF
[db-host]
$DB_IP
EOF

### link other instances to the db server
echo > $ANSIBLE_FILE_PATH/link-to-db.yml
cat >> $ANSIBLE_FILE_PATH/link-to-db.yml << EOL
---
  - name: link to the  wordpress database
    hosts: not-dbhost
    user: ubuntu
    sudo: true
    gather_facts: False
    tasks:
    - name: run wordpress db
      shell: docker run -d --name mysql_ambassador --expose 3306 -e DB_PORT_3306_TCP=tcp://$DB_IP:3306 svendowideit/ambassador
EOL

echo "[not-dbhost]" >> $ANSIBLE_FILE_PATH/hosts
aws ec2 describe-instances --filters Name=tag-value,Values=INFRA-"$APP_NAME"* |grep PublicIp |awk -F ':' '{print $2}' |sed 's/,//g' |sed 's/"//g' |sed 's/ //g' |sort |uniq |grep -v $DB_IP |while read d ;do

cat >> $ANSIBLE_FILE_PATH/hosts << EOT
$d
EOT
done

cat >> $ANSIBLE_FILE_PATH/install-docker.yml << EOF
  - name: install docker
    hosts: $APP_NAME-$ENV
    user: ubuntu
    sudo: true
    gather_facts: False
    tasks:
    - name: update apt
      shell: apt-get update
    - name: install apt-transport-https
      shell: apt-get install apt-transport-https ca-certificates
    - name: add key
      shell: apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    - name: add docker repo
      shell: echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list
    - name: update apt
      shell: apt-get update
    - name: install recommended packages
      shell: apt-get install linux-image-extra-$(uname -r) linux-image-extra-virtual -y
    - name: install docker version 1.10
      shell: apt-get install docker-engine=1.10.0-0~trusty -y
    - name: start docker service
      service: name=docker state=started
EOF

### install docker on the  instances

ansible-playbook -i $ANSIBLE_FILE_PATH/hosts $ANSIBLE_FILE_PATH/install-docker.yml
ansible-playbook -i $ANSIBLE_FILE_PATH/hosts $ANSIBLE_FILE_PATH/setup-db.yml -v 
ansible-playbook -i $ANSIBLE_FILE_PATH/hosts $ANSIBLE_FILE_PATH/link-to-db.yml -v 

### RUN the App inside docker containers



cat >> $ANSIBLE_FILE_PATH/create-docker-image.yml << EOF
  - name: create and run wordpress docker image
    hosts: $APP_NAME-$ENV
    user: ubuntu
    sudo: true
    gather_facts: False
    tasks:
    - name: create docker dir
      file: path=/opt/docker state=directory
    - name: copy docker files
      copy: src=$ANSIBLE_FILE_PATH/docker/Dockerfile dest=/opt/docker/Dockerfile
    - name: copy runme script tostart nginx process
      copy: src=$ANSIBLE_FILE_PATH/docker/runme.sh dest=/opt/docker/runme.sh
    - name: copy wordpress nginx config file
      copy: src=$ANSIBLE_FILE_PATH/docker/wordpress dest=/opt/docker/wordpress
    - name: build docker image
      shell:  docker build -t wordpress-nginx /opt/docker/
    - name: run the docker container 
      shell: docker run --name wordpress -p 80:80 --link mysql_ambassador:mysql -e WORDPRESS_DB_USER=infra -e WORDPRESS_DB_PASSWORD="Infra123qaz" -e WORDPRESS_DB_NAME=wordpress -d wordpress-nginx
    - name: start the nginx inside the container
      shell:  docker exec  wordpress bash /opt/runme.sh
EOF

## creat docker image 
ansible-playbook -i $ANSIBLE_FILE_PATH/hosts $ANSIBLE_FILE_PATH/create-docker-image.yml -v

### register EC2 instances to the LB
echo > $ANSIBLE_FILE_PATH/register_lb.yml
cat > $ANSIBLE_FILE_PATH/register_lb.yml << EOF
---
  - name: Register EC2 Instance
    hosts: 127.0.0.1
    gather_facts: False
    tasks:
EOF
### get the instances IDs

aws ec2 describe-instances --filters Name=tag-value,Values=INFRA-"$APP_NAME"* |grep InstanceId |awk -F ':' '{print $2}' |sed 's/,//g' |sed 's/"//g' |sed 's/ //g' |while read i;do 

cat >> $ANSIBLE_FILE_PATH/register_lb.yml << EOF
    - name: register EC2 instance
      local_action:
        module: ec2_elb
        instance_id: $i
        ec2_elbs: PUBLIC-LB
        state: 'present'
        region: us-west-2
EOF
done

ansible-playbook  $ANSIBLE_FILE_PATH/register_lb.yml
### get the loadBalancer DNS 
LB=`aws elb describe-load-balancers --load-balancer-name PUBLIC-LB |grep DNSName |awk -F ':' '{print $2}' |sed 's/,//g' |sed 's/"//g'`
echo "You can access the LoadBalanced WordPress app using this domain $LB"

