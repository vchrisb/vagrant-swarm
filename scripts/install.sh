#!/bin/bash
while [[ $# > 1 ]]
do
  key="$1"

  case $key in
    -d|--device)
    DEVICE="$2"
    shift
    ;;
    -f|--firstmdmip)
    FIRSTMDMIP="$2"
    shift
    ;;
    -s|--secondmdmip)
    SECONDMDMIP="$2"
    shift
    ;;
    -t|--tbip)
    TBIP="$2"
    shift
    ;;
    -p|--password)
    PASSWORD="$2"
    shift
    ;;
    -n|--nodetype)
    TYPE="$2"
    shift
    ;;
    *)
    # unknown option
    ;;
  esac
  shift
done

echo DEVICE  = "${DEVICE}"
echo FIRSTMDMIP    = "${FIRSTMDMIP}"
echo SECONDMDMIP    = "${SECONDMDMIP}"
echo TBIP    = "${TBIP}"
echo PASSWORD    = "${PASSWORD}"

# install golang
#cd /tmp
#wget -N -nv https://storage.googleapis.com/golang/go1.7.linux-amd64.tar.gz
#sudo tar -C /usr/local -xzf go1.7.linux-amd64.tar.gz
#echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/path.sh

# install rexray
echo "#### Installing RexRay ####"
curl -sSL https://dl.bintray.com/emccode/rexray/install | sh -
cat > /etc/rexray/config.yml <<EOL
rexray:
  storageDrivers:
  - ScaleIO
  volume:
    mount:
      preempt: true
ScaleIO:
  endpoint: https://${FIRSTMDMIP}:8080/api
  insecure: true
  userName: admin
  password: Scaleio123
  systemName: Vagrant
  protectionDomainName: pd1
  storagePoolName: sp1
EOL
chmod 0664 /etc/rexray/config.yml
rexray start

# install and start docker
echo "#### Installing docker ####"
curl -fsSL https://get.docker.com/ | sh
service docker start

# install ScaleIO and configure Swarm
case "$(uname -r)" in
  *el6*)
    sysctl -p kernel.shmmax=209715200
    yum install numactl libaio -y
    cd /vagrant/scaleio/ScaleIO*/ScaleIO*RHEL6*
    ;;
  *el7*)
    yum install numactl libaio -y
    cd /vagrant/scaleio/ScaleIO*/ScaleIO*RHEL7*
    ;;
esac

if  [[ "tb mdm1 mdm2" = *${TYPE}* ]]; then
	echo "#### Installing ScaleIO SDC and LIA ####"
    truncate -s 100GB ${DEVICE}
    rpm -Uv EMC-ScaleIO-sds-*.x86_64.rpm
    MDM_IP=${FIRSTMDMIP},${SECONDMDMIP} rpm -Uv EMC-ScaleIO-sdc-*.x86_64.rpm
    TOKEN=${PASSWORD} rpm -Uv EMC-ScaleIO-lia-*.x86_64.rpm
fi

case ${TYPE} in
	"tb")
		echo "#### Installing ScaleIO MDM ####"
		MDM_ROLE_IS_MANAGER=0 rpm -Uv EMC-ScaleIO-mdm-*.x86_64.rpm
		echo "#### Creating docker swarm ####"
		docker swarm init --listen-addr ${TBIP} --advertise-addr ${TBIP}
		docker swarm join-token -q manager > /vagrant/swarm_manager_token
		;;

	"mdm2")
		echo "#### Installing ScaleIO MDM ####"
		MDM_ROLE_IS_MANAGER=1 rpm -Uv EMC-ScaleIO-mdm-*.x86_64.rpm
		
		echo "#### Joining docker swarm as manager ####"
		MANAGER_TOKEN=`cat /vagrant/swarm_manager_token`
		docker swarm join --listen-addr ${SECONDMDMIP} --advertise-addr ${SECONDMDMIP} --token=$MANAGER_TOKEN ${TBIP}
		;;

	"mdm1")
		echo "#### Installing ScaleIO MDM ####"
		MDM_ROLE_IS_MANAGER=1 rpm -Uv EMC-ScaleIO-mdm-*.x86_64.rpm
		
		echo "#### Creating and configuring ScaleIO Cluster ####"
		scli --create_mdm_cluster --master_mdm_ip ${FIRSTMDMIP} --master_mdm_management_ip ${FIRSTMDMIP} --master_mdm_name mdm1 --accept_license --approve_certificate
		sleep 5
		scli --login --username admin --password admin
		scli --set_password --old_password admin --new_password ${PASSWORD}
		scli --login --username admin --password ${PASSWORD}
		scli --rename_system --new_name Vagrant
		scli --add_standby_mdm --new_mdm_ip ${SECONDMDMIP} --mdm_role manager --new_mdm_management_ip ${SECONDMDMIP} --new_mdm_name mdm2
		scli --add_standby_mdm --new_mdm_ip ${TBIP} --mdm_role tb --new_mdm_name tb1
		scli --switch_cluster_mode --cluster_mode 3_node --add_slave_mdm_name mdm2 --add_tb_name tb1
		sleep 2
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_protection_domain --protection_domain_name pd1
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_storage_pool --protection_domain_name pd1 --storage_pool_name sp1
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_sds --sds_ip ${FIRSTMDMIP} --device_path ${DEVICE} --storage_pool_name sp1 --protection_domain_name pd1 --sds_name sds1
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_sds --sds_ip ${SECONDMDMIP} --device_path ${DEVICE} --storage_pool_name sp1 --protection_domain_name pd1 --sds_name sds2
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_sds --sds_ip ${TBIP} --device_path ${DEVICE} --storage_pool_name sp1 --protection_domain_name pd1 --sds_name sds3		
		sleep 2
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --query_all
		
		echo "#### Joining docker swarm as manager ####"
		MANAGER_TOKEN=`cat /vagrant/swarm_manager_token`
		docker swarm join --listen-addr ${FIRSTMDMIP} --advertise-addr ${FIRSTMDMIP} --token=$MANAGER_TOKEN ${TBIP}
		
		echo "#### Starting ScaleIO Gateway on docker swarm ####"
		docker service create --replicas 2 --name=scaleio-gw -p 8080:443 -e GW_PASSWORD=${PASSWORD} -e MDM1_IP_ADDRESS=${FIRSTMDMIP} -e MDM2_IP_ADDRESS=${SECONDMDMIP} -e TRUST_MDM_CRT=true vchrisb/scaleio-gw
		
		TIMEOUT=1200
		TIMER=1
		INTERVAL=30
		echo "#### Wating for ScaleIO Gateway to become available (Timeout after ${TIMEOUT}s) ####"
		while [[ $(curl --output /dev/null --head --silent --fail --insecure --write-out %{http_code} https://${FIRSTMDMIP}:8080) != 302 ]];
		do
		  if [ $TIMER -gt $TIMEOUT ]; then
			echo ""
			echo "ScaleIO Gateway Container did not start in a timely (${TIMEOUT}s) fashion!" >&2
			echo "Service start may have been delayed or failed." >&2
			exit 1
		  fi
		  printf "."
		  sleep $INTERVAL
		  let TIMER=TIMER+$INTERVAL
		done
		echo ""
		echo "Docker Swarm with persistent storage using ScaleIO and RexRay successfully deployed!"
		echo "Follwing example does start a Mariadb Server using persistent storage:"
		echo "sudo docker service create --name mariadb --mount type=volume,volume-driver=rexray,source="mariadb",target=/var/lib/mysql -e MYSQL_ROOT_PASSWORD=test mariadb"
		echo ""
		;;
esac



if [[ -n $1 ]]; then
  echo "Last line of file specified as non-opt/last argument:"
  tail -1 $1
fi
