terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.34.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
  access_key = "XXXXXXXX"
  secret_key = "XXXXXXXX"
}

# 1.Create VPC
resource "aws_vpc" "lab-VPC" {
  cidr_block = "192.168.0.0/16" #CIDR Block
  enable_dns_hostnames = true #enable dns host name for private IPs in this VPC
  tags = {
    Name = "Lab-VPC"
  }
}

# 2.Create IGW

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.lab-VPC.id

  tags = {
    Name = "lab-igw"
  }
}

# 3.Create Public Route Table

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.lab-VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

#4.Create Private Route Table

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.lab-VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    network_interface_id = aws_network_interface.private-nic.id #call the interface id
    
  }

  route {
    ipv6_cidr_block        = "::/0"
    network_interface_id = aws_network_interface.private-nic.id #call the interface id
  }

  tags = {
    Name = "private-rt"
  }
}
# 5.Create a Public Subnet

resource "aws_subnet" "public-subnet" {
    vpc_id = aws_vpc.lab-VPC.id
    cidr_block = "192.168.1.0/24"
    availability_zone = "us-east-1a" # Specify the AZ
    tags = {
    Name = "public-subnet"
  }
}

# 6.Create a Private Subnet

resource "aws_subnet" "private-subnet" {
    vpc_id = aws_vpc.lab-VPC.id
    cidr_block = "192.168.2.0/24"
    availability_zone = "us-east-1a" # Specify the AZ
    tags = {
    Name = "private-subnet"
  }
}

# 7.Create a management Subnet

resource "aws_subnet" "management-subnet" {
    vpc_id = aws_vpc.lab-VPC.id
    cidr_block = "192.168.3.0/24"
    availability_zone = "us-east-1a" # Specify the AZ
    tags = {
    Name = "management-subnet"
  }
}

# 8.Associate subnet with route table
resource "aws_route_table_association" "sub-asso" {
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "sub-asso" {
  subnet_id      = aws_subnet.management-subnet.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "pri-sub-asso" {
  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private-route-table.id
}

# 9.Create Secruity Group to allow port 22,80,ICMP
resource "aws_security_group" "allow_mgmt" {
  name        = "allow_mgmt_traffic"
  description = "Allow SSH,ping inbound traffic"
  vpc_id      = aws_vpc.lab-VPC.id

  tags = {
    Name = "allow_mgmt"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_port_SSH" {
  security_group_id = aws_security_group.allow_mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_port_80" {
  security_group_id = aws_security_group.allow_mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_port_ping" {
  security_group_id = aws_security_group.allow_mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  ip_protocol       = "icmp"
  to_port           = -1
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_mgmt.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# 10.Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "public-nic" {
  subnet_id       = aws_subnet.public-subnet.id
  security_groups = [aws_security_group.allow_mgmt.id]
  source_dest_check = false
   tags = {
    Name = "public-NIC"
  }
}

resource "aws_network_interface" "private-nic" {
  subnet_id       = aws_subnet.private-subnet.id
  security_groups = [aws_security_group.allow_mgmt.id]
  source_dest_check = false
   tags = {
    Name = "private-NIC"
  }
}

#11. Create ec2 server and install/enable apache2
resource "aws_instance" "ec2-instance" {
    ami = "ami-0277155c3f0ab2930"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "mykeypair"
    vpc_security_group_ids = [aws_security_group.allow_mgmt.id]
    subnet_id = aws_subnet.private-subnet
    user_data = "${file("user-data.sh")}" #to bootstrap the ec2
    
    tags = {
            Name = "Ec2Instance"
        }
}

#12.Create Palo Alto instance and attach to the interface
resource "aws_instance" "palo_alto" {
  ami           = "ami-0a4ee1cb51559e095"
  availability_zone = "us-east-1a"
  instance_type = "c5n.xlarge"
  key_name      = "mykeypair"
  vpc_security_group_ids = [aws_security_group.allow_mgmt.id]
  subnet_id = aws_subnet.management-subnet.id
  associate_public_ip_address = true


  tags = {
    Name = "palo-alto-vm"
  }
}