vagrant-swarm
---------------

# Description

Vagrantfile to create a three node Docker Swarm cluster using [ScaleIO](https://www.emc.com/products-solutions/trial-software-download/scaleio.htm) and [Rex-Ray](https://github.com/emccode/rexray).

# Usage

This Vagrant setup will automatically deploy three CentOS 7.2 nodes, download the ScaleIO 2.0 software and install a full ScaleIO cluster.
Furthermore a Docker Swarm cluster is created and support for persistent storage is added using Rex-Ray!

To use this, you'll need to complete a few steps:

1. `git clone https://github.com/vchrisb/vagrant-swarm.git`
2. Run `vagrant up`
3. Login into one node: `vagrant ssh node1`
3. Login into ScaleIO: `scli --mdm_ip 192.168.100.11,192.168.100.12 --login --username admin --password Scaleio123 --approve_certificate`
4. Validate ScaleIO; `scli --mdm_ip 192.168.100.11,192.168.100.12 --query_all`
5. Validate docker swarm: `docker node ls`
6. Validate RexRay: `docker volume ls`

# Example workload

### Running stateful Wordpress:

1. Create network for communication between wordpress and mariadb: `docker network create --driver overlay wp_nw`
2. Create volume for mariadb: `docker volume create -d scaleio --name wp_db`
3. Create volume for wordpress: `docker volume create -d scaleio --name wp_content`
4. Start mariadb: `docker service create --name wordpress_db --network wp_nw --mount type=volume,volume-driver=scaleio,source="wp_db",target=/var/lib/mysql -e MYSQL_ROOT_PASSWORD=Passw0rd mariadb`
5. Start wordpress: `docker service create --name wordpress --network wp_nw --mount type=volume,volume-driver=scaleio,source="wp_content",target=/var/www/html/wp-content -e WORDPRESS_DB_HOST=wordpress_db -e WORDPRESS_DB_PASSWORD=Passw0rd -p 80:80 wordpress`
6. Access wordpress on any of the nodes: `http://192.168.100.11`
7. Create some sample content

### Test failure:

1. Remove wordpress `docker service rm wordpress`
2. Remove mariadb `docker service rm wordpress_db`
3. Start mariadb: `docker service create --name wordpress_db --network wp_nw --mount type=volume,volume-driver=scaleio,source="wp_db",target=/var/lib/mysql -e MYSQL_ROOT_PASSWORD=Passw0rd mariadb`
4. Start wordpress: `docker service create --name wordpress --network wp_nw --mount type=volume,volume-driver=scaleio,source="wp_content",target=/var/www/html/wp-content -e WORDPRESS_DB_HOST=wordpress_db -e WORDPRESS_DB_PASSWORD=Passw0rd -p 80:80 wordpress`
5. Access wordpress on any of the nodes: `http://192.168.100.11` and validate that it kept your content!

# Troubleshooting

If anything goes wrong during the deployment, run `vagrant destroy -f` to remove all the VMs and then `vagrant up` again to restart the deployment.
