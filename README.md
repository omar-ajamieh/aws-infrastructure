# aws-infrastructure
In This Repo you will find a set of Ansible playbooks and a bash script and these scripts are used to create a AWS enviroment (EC2 instances, Load Balancer,Security groups) also it will install and start a wordpress app with nginx web server inside a docker machine and setup a shared docker mysql database, then it will add the EC2 instances to a load balancer and will give you the public dns for it in order to access the wordpress

# Usage

bash cloud-automation.sh app environment num_servers server_size

# Example


bash cloud-automation.sh hello_wolrd production 3 t2.micro
