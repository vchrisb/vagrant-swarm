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

# restart network as private network sometimes not yet available
systemctl restart network

# install and start docker
echo "#### Installing docker ####"
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://docs.docker.com/engine/installation/linux/repo_files/centos/docker.repo
sudo yum makecache fast 
sudo yum -y install docker-engine
sudo systemctl enable docker
sudo systemctl start docker
sudo gpasswd -a vagrant docker

# install ScaleIO and configure Swarm
case "$(uname -r)" in
  *el6*)
    sysctl -p kernel.shmmax=209715200
    yum install numactl libaio -y
    cd /vagrant/scaleio/ScaleIO*/ScaleIO*RHEL_OEL6*
    ;;
  *el7*)
    yum install numactl libaio -y
    cd /vagrant/scaleio/ScaleIO*/ScaleIO*RHEL_OEL7*
    ;;
esac

if  [[ "tb mdm1 mdm2" = *${TYPE}* ]]; then
	echo "#### Installing ScaleIO SDC and LIA ####"
    truncate -s 100GB ${DEVICE}
    rpm -Uv EMC-ScaleIO-sds-*.x86_64.rpm
    MDM_IP=${FIRSTMDMIP},${SECONDMDMIP} rpm -Uv EMC-ScaleIO-sdc-*.x86_64.rpm
    TOKEN=${PASSWORD} rpm -Uv EMC-ScaleIO-lia-*.x86_64.rpm
fi

# install rexray
docker plugin install rexray/scaleio --alias scaleio --grant-all-permissions \
  REXRAY_FSTYPE=xfs \
  REXRAY_LOGLEVEL=warn \
  REXRAY_PREEMPT=true \
  SCALEIO_ENDPOINT=https://127.0.0.1:8443/api \
  SCALEIO_INSECURE=true \
  SCALEIO_USERNAME=admin \
  SCALEIO_PASSWORD=${PASSWORD} \
  SCALEIO_SYSTEMNAME=Vagrant \
  SCALEIO_PROTECTIONDOMAINNAME=pd1 \
  SCALEIO_STORAGEPOOLNAME=sp1 \
  SCALEIO_THINORTHICK=ThinProvisioned

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
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_protection_domain --protection_domain_name pd1 --approve_certificate
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_storage_pool --protection_domain_name pd1 --storage_pool_name sp1 --approve_certificate
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_sds --sds_ip ${FIRSTMDMIP} --device_path ${DEVICE} --storage_pool_name sp1 --protection_domain_name pd1 --sds_name sds1 --approve_certificate
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_sds --sds_ip ${SECONDMDMIP} --device_path ${DEVICE} --storage_pool_name sp1 --protection_domain_name pd1 --sds_name sds2 --approve_certificate
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --add_sds --sds_ip ${TBIP} --device_path ${DEVICE} --storage_pool_name sp1 --protection_domain_name pd1 --sds_name sds3 --approve_certificate
		sleep 2
		scli --mdm_ip ${FIRSTMDMIP},${SECONDMDMIP} --query_all --approve_certificate
		
		echo "#### Joining docker swarm as manager ####"
		MANAGER_TOKEN=`cat /vagrant/swarm_manager_token`
		docker swarm join --listen-addr ${FIRSTMDMIP} --advertise-addr ${FIRSTMDMIP} --token=$MANAGER_TOKEN ${TBIP}
		
		echo "#### Starting ScaleIO Gateway on docker swarm ####"
		docker service create --replicas 2 --name=scaleio-gw -p 8443:443 -e GW_PASSWORD=${PASSWORD} -e MDM1_IP_ADDRESS=${FIRSTMDMIP} -e MDM2_IP_ADDRESS=${SECONDMDMIP} -e TRUST_MDM_CRT=true vchrisb/scaleio-gw
		
		TIMEOUT=1200
		TIMER=1
		INTERVAL=30
		echo "#### Wating for ScaleIO Gateway being downloaded and becoming available (Timeout after ${TIMEOUT}s) ####"
		while [[ $(curl --output /dev/null --head --silent --fail --insecure --write-out %{http_code} https://${FIRSTMDMIP}:8443) != 302 ]];
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
		echo ""
		;;
esac



if [[ -n $1 ]]; then
  echo "Last line of file specified as non-opt/last argument:"
  tail -1 $1
fi
