# scaleio admin password
password="Scaleio123"

# add your domain here
domain = 'scaleio.local'

# add your IPs here
network = "192.168.100"
firstmdmip = "#{network}.11"
secondmdmip = "#{network}.12"
tbip = "#{network}.13"

# modifiy hostnames if required
nodes = [
{hostname: "node1", ipaddress: "#{tbip}", type: "tb", box: "bento/centos-7.3", memory: "1024"},
{hostname: 'node2', ipaddress: "#{secondmdmip}", type: 'mdm2', box: "bento/centos-7.3", memory: "1024"},
{hostname: 'node3', ipaddress: "#{firstmdmip}", type: 'mdm1', box: "bento/centos-7.3", memory: "1024"},
]

# 100GB fake device
device = "/home/vagrant/scaleio1"

Vagrant.configure("2") do |config|
  # try to enable caching to speed up package installation for second run
  if Vagrant.has_plugin?("vagrant-cachier")
    config.cache.scope = :box
  end

  nodes.each do |node|
    config.vm.define node[:hostname] do |node_config|
      node_config.vm.box = "#{node[:box]}"
      node_config.vm.host_name = "#{node[:hostname]}.#{domain}"
      node_config.vm.provider :virtualbox do |vb|
        vb.customize ["modifyvm", :id, "--memory", "#{node[:memory]}"]
      end
      node_config.vm.network "private_network", ip: "#{node[:ipaddress]}"

      # update box
      #node_config.vm.provision "update", type: "shell", path: "scripts/update.sh"

      if node[:type] == "tb"
        # download latest ScaleIO bits
        node_config.vm.provision "download", type: "shell", path: "scripts/download.sh"
      end

      node_config.vm.provision "shell" do |s|
        s.path = "scripts/install.sh"
        s.args   = "-d #{device} -f #{firstmdmip} -s #{secondmdmip} -t #{tbip} -p #{password} -n #{node[:type]}"
      end

    end
  end
end
