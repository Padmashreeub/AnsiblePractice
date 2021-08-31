## Creation of Couchdb cluster and adding nodes to the cluster

## Installing pacakges

```yaml
- name: Add apache-couchdb repo
  yum_repository:
    name: bintray--apache-couchdb-rpm
    description: bintray--apache-couchdb-rpm
    baseurl: http://apache.bintray.com/couchdb-rpm/el$releasever/$basearch/
    gpgcheck: no

- name: Install epel-release
  yum:
    name: epel-release  
    state: present
    update_cache: yes

- name: Install couchdb
  yum:
    name: couchdb    
    state: present
    update_cache: yes
```
## Updating server Public IP in configuration
```yaml
- name: Get public IP
  ipify_facts:
  register: public_ip

- name: Getting public IP
  set_fact:
    public_ip_address: "{{ public_ip['ansible_facts']['ipify_public_ip'] }}"

- debug:
    var: public_ip_address

- name: Changing IP to public IP
  lineinfile:
    path: /opt/couchdb/etc/vm.args
    regexp: '^-name couchdb@127.0.0.1'
    line: '-name couchdb@{{ public_ip_address }}'
    backrefs: yes
```
## Adding port details in configuration file
```yaml
 name: Test for line
  shell: grep 'kernel inet_dist_listen_min 9100' /opt/couchdb/etc/vm.args
  register: test_grep
  ignore_errors: yes

- name: Adding ports
  lineinfile:
    path: /opt/couchdb/etc/vm.args
    line: "{{ item}}"
  with_items:
    - '-kernel inet_dist_listen_min 9100'
    - '-kernel inet_dist_listen_max 9200'
  when: test_grep.stdout == ""
```
## Starting and enabling couchdb service
```yaml
- name: Make sure couchdb service is service is running and enabled
  systemd:
    state: started
    name: couchdb
    enabled: yes
```
## Generationg UUIDs and saving to a file
```yaml
- name: Checking uuid files already exists locally
  stat:
    path: "{{ UUID_dir }}/uuid_0"
  delegate_to: localhost
  register: stat_result

- name: Generating UUIDs
  shell: curl -s http://127.0.0.1:5984/_uuids?count=2
  register: uuids
  when: stat_result.stat.exists == False

- name: Setting uuid variables
  set_fact:
    uuids_parsed: "{{ uuids.stdout | from_json }}"
  when: stat_result.stat.exists == False

- name: Getting uuids
  set_fact:
    uuids_list: "{{ uuids_parsed['uuids'] }}"
  when: stat_result.stat.exists == False

- name: Creating UUID directory
  file:
    path: "{{ UUID_dir }}"
    state: directory
  delegate_to: localhost
  when: stat_result.stat.exists == False

- name: Write UUIDS to files
  copy:
    dest: "{{ UUID_dir }}/uuid_{{ item.0 }}"
    content: "{{ item.1 }}"
  with_indexed_items: "{{ uuids_list }}"
  delegate_to: localhost
  when: stat_result.stat.exists == False
```
## Creating admin user and using the same UUIDs in all the nodes
```yaml
- name: Creating admin password
  shell: curl -sX PUT http://127.0.0.1:5984/_node/_local/_config/admins/{{ admin_username }} -d '"{{ password }}"'

- name: Binding the clustered interface to all IP addresses availble on this machine
  shell: curl -sX PUT http://{{ admin_username}}:{{ password }}@127.0.0.1:5984/_node/_local/_config/chttpd/bind_address -d '"0.0.0.0"'

- name: Setting the UUID of the node to the first UUID you previously obtained
  shell: curl -sX PUT http://{{ admin_username}}:{{ password }}@127.0.0.1:5984/_node/_local/_config/couchdb/uuid -d '"{{ uuid_1 }}"'

- name: Setting the shared http secret for cookie creation to the second UUID
  shell: curl -sX PUT http://{{ admin_username}}:{{ password }}@127.0.0.1:5984/_node/_local/_config/couch_httpd_auth/secret -d '"{{ uuid_2 }}"'
```
## Setting IP of one the node as cordination IP and saving it to a file
```yaml
- name: Initializing every node for cluster
  shell: curl -sX POST -H "Content-Type":" application/json" http://admin:password@{{ public_ip_address }}:5984/_cluster_setup -d '{"action":"enable_cluster", "bind_address":"0.0.0.0", "username":"admin", "password":"password", "node_count":"3"}'

- name: Checking setup_cordination_ip file is already exists locally
  stat:
    path: "{{ playbook_dir }}/setup_cordination_ip"
  delegate_to: localhost
  register: stat_result_setup_cordination_ip

- name: Creating setup_cordination_ip file
  copy:
    dest: "{{ playbook_dir }}/setup_cordination_ip"
    content: "{{ public_ip_address }}"
  delegate_to: localhost
  when: stat_result_setup_cordination_ip.stat.exists == False
```
## Adding nodes to cluster and creating system database
```yaml
 name: Joining node to cluster
  shell: curl -sX POST -H "Content-Type":" application/json" http://admin:password@{{ setup_cordination_ip }}:5984/_cluster_setup -d '{"action":"enable_cluster", "bind_address":"0.0.0.0", "port":5984, "username":"{{ admin_username }}", "password":"{{ password }}", "node_count":"3", "remote_node":"{{ public_ip_address }}", "remote_current_user":"{{ admin_username }}", "remote_current_password":"{{ password }}" }'
  when: setup_cordination_ip != public_ip_address

- name: Adding node to cluster
  shell: curl -sX POST -H "Content-Type":" application/json" http://admin:password@{{ setup_cordination_ip }}:5984/_cluster_setup -d '{"action":"add_node", "host":"{{ public_ip_address }}", "port":5984, "username":"{{ admin_username }}", "password":"{{ password }}"}'
  when: setup_cordination_ip != public_ip_address

- name: Adding system database
  shell: curl -sX POST -H "Content-Type":" application/json" http://admin:password@{{ setup_cordination_ip }}:5984/_cluster_setup -d '{"action":"finish_cluster"}'
  when: setup_cordination_ip == public_ip_address

- name: Checking cluster status
  shell: curl -s http://admin:password@{{ setup_cordination_ip }}:5984/_cluster_setup
```
## For adding new nodes and transfer the shards to the new node
Execute below curl command from any of the existing nodes in the cluster
```shell
curl -X PUT "http://localhost:5986/_nodes/node2@yyy.yyy.yyy.yyy" -d {}
```
where **node2@yyy.yyy.yyy.yyy** is the new node name which is set in the conf file

## Putting target node in maintainance mode
To enable maintenance mode:
```shell
$ curl -X PUT -H "Content-type: application/json" \
$COUCH_URL:5984/_node/<nodename>/_config/couchdb/maintenance_mode \
    -d "\"true\""
```


## Copying shard files
Using **scp** copy shard files from the source node to the target node.
```shell
# On the new node
$ mkdir -p data/.shards/<range>
$ mkdir -p data/shards/<range>
# From the source node
$ scp <couch-dir>/data/.shards/<range>/<database>.<datecode>* \
  <node>:<couch-dir>/data/.shards/<range>/
$ scp <couch-dir>/data/shards/<range>/<database>.<datecode>.couch \
  <node>:<couch-dir>/data/shards/<range>/
```


## Copying shard to another node
Below command will give cluster metadata and how shards are stored
```shell
curl -s http://admin:password@localhost:5986/_dbs/my_database | jq .
``` 
And the output will be like this
```shell
{
  "_id": "my_database",
  "_rev": "6-ae0e3f55c3f524add19790a47e784a40",
  "shard_suffix": [
    46,
    49,
    53,
    54,
    53,
    54,
    57,
    50,
    57,
    50,
    55
  ],
  "changelog": [
    [
      "add",
      "00000000-1fffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "20000000-3fffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "40000000-5fffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "60000000-7fffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "80000000-9fffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "a0000000-bfffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "c0000000-dfffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "e0000000-ffffffff",
      "couchdb@13.127.228.124"
    ],
    [
      "add",
      "00000000-1fffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "00000000-1fffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "00000000-1fffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "20000000-3fffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "20000000-3fffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "20000000-3fffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "40000000-5fffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "40000000-5fffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "40000000-5fffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "60000000-7fffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "60000000-7fffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "60000000-7fffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "80000000-9fffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "80000000-9fffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "80000000-9fffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "a0000000-bfffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "a0000000-bfffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "a0000000-bfffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "c0000000-dfffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "c0000000-dfffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "c0000000-dfffffff",
      "couchdb@13.234.217.66"
    ],
    [
      "add",
      "e0000000-ffffffff",
      "couchdb@13.233.173.52"
    ],
    [
      "add",
      "e0000000-ffffffff",
      "couchdb@13.233.184.94"
    ],
    [
      "add",
      "e0000000-ffffffff",
      "couchdb@13.234.217.66"
    ]
  ],
  "by_node": {
    "couchdb@13.127.228.124": [
      "00000000-1fffffff",
      "20000000-3fffffff",
      "40000000-5fffffff",
      "60000000-7fffffff",
      "80000000-9fffffff",
      "a0000000-bfffffff",
      "c0000000-dfffffff",
      "e0000000-ffffffff"
    ],
    "couchdb@13.233.173.52": [
      "00000000-1fffffff",
      "20000000-3fffffff",
      "40000000-5fffffff",
      "60000000-7fffffff",
      "80000000-9fffffff",
      "a0000000-bfffffff",
      "c0000000-dfffffff",
      "e0000000-ffffffff"
    ],
    "couchdb@13.233.184.94": [
      "00000000-1fffffff",
      "20000000-3fffffff",
      "40000000-5fffffff",
      "60000000-7fffffff",
      "80000000-9fffffff",
      "a0000000-bfffffff",
      "c0000000-dfffffff",
      "e0000000-ffffffff"
    ],
    "couchdb@13.234.217.66": [
      "00000000-1fffffff",
      "20000000-3fffffff",
      "40000000-5fffffff",
      "60000000-7fffffff",
      "80000000-9fffffff",
      "a0000000-bfffffff",
      "c0000000-dfffffff",
      "e0000000-ffffffff"
    ]
  },
  "by_range": {
    "00000000-1fffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "20000000-3fffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "40000000-5fffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "60000000-7fffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "80000000-9fffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "a0000000-bfffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "c0000000-dfffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ],
    "e0000000-ffffffff": [
      "couchdb@13.233.173.52",
      "couchdb@13.233.184.94",
      "couchdb@13.234.217.66",
      "couchdb@13.127.228.124"
    ]
  }
}
```
Copy this outout and paste in the a text file and update **changelog**, **by_node** and **by_range** sections by adding the new node part  in every sections

For updating the new change, execute below command
```shell
curl -X PUT http://localhost:5986/_dbs/{name} -d @json_file
```
## For removing the shards from source node
For removing shards from source node
```shell
$ rm <couch-dir>/data/shards/<range>/<dbname>.<datecode>.couch
$ rm -r <couch-dir>/data/.shards/<range>/<dbname>.<datecode>*
```
When removing a shard from a node, specify `remove` instead of `add`. in cluster metadata and also the finally you will need to update the `by_node` and `by_range` to reflect who is storing what shards. The data in the changelog entries and these attributes must match. If they do not, the database may become corrupted.


## Update admin user and password

Admin user and password for the admin user in all nodes in the cluster can  be set in the **var/main.yml file** 

```yaml
password: "password"
admin_username: "admin"
```

## Documentation
[Couchdb documentation](https://docs.couchdb.org/en/stable/)
