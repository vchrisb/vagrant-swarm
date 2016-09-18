#!/bin/bash

yum -y install wget unzip
cd /vagrant
echo "#### Downloading and extracting ScaleIO binaries ####"
wget -N -nv http://downloads.emc.com/emc-com/usa/ScaleIO/ScaleIO_Linux_v2.0.zip
unzip -q -o ScaleIO_Linux_v2.0.zip -d /vagrant/scaleio/
