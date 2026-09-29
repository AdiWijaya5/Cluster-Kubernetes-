# Menampilkan IP Publik untuk akses SSH
output "server_public_ips" {
  description = "Alamat IP Publik (Elastic IP) untuk akses SSH"
  value = {
    for idx, node in aws_instance.k8s_nodes : 
    local.server_hostnames[idx] => aws_eip.k8s_eip[idx].public_ip
  }
}

# Menampilkan ID Instance
output "server_instance_ids" {
  description = "ID Instance AWS server"
  value = {
    for idx, node in aws_instance.k8s_nodes : 
    local.server_hostnames[idx] => node.id
  }
}

# Menampilkan ID Block Storage tambahan
output "ebs_storage_ids" {
  description = "ID Volume EBS tambahan"
  value = {
    for idx, vol in aws_ebs_volume.k8s_storage : 
    local.server_hostnames[idx] => vol.id
  }
}