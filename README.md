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
3. Start a container with persistence: `sudo docker service create --name mariadb --mount type=volume,volume-driver=rexray,source="mariadb",target=/var/lib/mysql -e MYSQL_ROOT_PASSWORD=test mariadb`

# Troubleshooting

If anything goes wrong during the deployment, run `vagrant destroy -f` to remove all the VMs and then `vagrant up` again to restart the deployment.
