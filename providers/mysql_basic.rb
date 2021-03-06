action :install_grants do

ndb_waiter "wait_ndb_started" do
  action :wait_until_cluster_ready
  only_if { node[:ndb][:enabled] == "true" }
end

ndb_mysql_basic "mysqld_start_grants" do
  wait_time 10
  remove_mycnf 1
  action :wait_until_started
end


grants_path = "#{Chef::Config[:file_cache_path]}/grants.sql"

exec="/var/lib/mysql-cluster/ndb/scripts/mysql-client.sh"
bash 'run_grants' do
    user node[:ndb][:user]
    code <<-EOF
     export MYSQL_HOME=#{node[:ndb][:root_dir]}
     #{node[:ndb][:scripts_dir]}/mysql-client.sh -e "source #{grants_path}"
    EOF
    new_resource.updated_by_last_action(true)
    not_if "#{node[:mysql][:base_dir]}/bin/mysql -u root #{node[:mysql][:root][:password].empty? ? '' : '-p' }#{node[:mysql][:root][:password]} -S #{node[:ndb][:mysql_socket]} -e \"SELECT user FROM mysql.user WHERE host LIKE '\%';\"  | grep root"
  end
end

action :wait_until_started do

# mysql_install_db makes a copy of the my.cnf file in /etc/mysql. Remove it.
# FC021 for the next line's new_resource.name attribute
bash "remove_mycnf_#{new_resource.name}" do
    user node[:ndb][:user]
    code <<-EOF
     if [ -f /etc/mysql/my.cnf ] ; then
         rm /etc/mysql/my.cnf  
     fi
    EOF
    only_if { new_resource.remove_mycnf == 1 }
end

bash 'wait_mysqld_started' do
    user node[:ndb][:user]
    code <<-EOF

    service mysqld restart
    sleep 5
    if [ `#{node[:mysql][:base_dir]}/bin/mysqladmin -u root -S #{node[:ndb][:mysql_socket]} status` -ne 0 ] ; then
     wait=new_resource.wait_time
     timeout=0
     while [ $timeout -lt $wait ] ; do
         echo -n "."
         sleep 1
         if [ `#{node[:mysql][:base_dir]}/bin/mysqladmin -u root -S #{node[:ndb][:mysql_socket]} status` -eq 0 ] ; then
           timeout=new_resource.wait_time
         fi
         timeout=`expr $timeout + 1`
     done
      # If it did't work, try starting it again...
        if [ `#{node[:mysql][:base_dir]}/bin/mysqladmin -u root -S #{node[:ndb][:mysql_socket]} status` -ne 0 ] ; then
          service mysqld start
          sleep new_resource.wait_time
        fi
    fi

    # The mysqld may really not have started...
    if [ `#{node[:mysql][:base_dir]}/bin/mysqladmin -u root -S #{node[:ndb][:mysql_socket]} status` -ne 0 ] ; then
       echo "Something went badly wrong. Couldn't start mysqld. Trying to reinstall. Backing up to #{node[:ndb][:base_dir]}/backup_mysql/"
       mkdir -p node[:ndb][:base_dir]/backup_mysql
       mv node[:ndb][:mysql_server_dir]/* node[:ndb][:base_dir]/backup_mysql/
       export MYSQL_HOME=#{node[:ndb][:root_dir]}
       cd #{node[:mysql][:base_dir]}
       ./scripts/mysql_install_db --user=#{node[:mysql][:run_as_user]} --basedir=#{node[:mysql][:base_dir]} --defaults-file=#{node[:ndb][:root_dir]}/my.cnf --force
       service mysqld start
       sleep new_resource.wait_time
    fi

    if [ `#{node[:mysql][:base_dir]}/bin/mysqladmin -u root -S #{node[:ndb][:mysql_socket]} status` -ne 0 ] ; then
         exit 1
    fi
    EOF
    not_if "#{node[:mysql][:base_dir]}/bin/mysqladmin -u root -S #{node[:ndb][:mysql_socket]} status"
  end

  Chef::Log.info "MySQL Server has started."
  new_resource.updated_by_last_action(false)
end
