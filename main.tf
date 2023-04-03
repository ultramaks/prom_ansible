terraform {
  required_providers {
    aws = {
      source             = "hashicorp/aws"
      version            = "~> 4.16"
    }
  }

  required_version       = ">= 1.2.0"
}

# Install provider
provider "aws" {
  region                 = "eu-central-1"
}

# Create VPC
resource "aws_vpc" "Test_Linux_VPC" {
  cidr_block             = "10.0.0.0/16"
  
  tags = {
    Name                 = "Test_Linux_VPC"
  }
}

# Create public Subnet
resource "aws_subnet" "test_public_subnet" {
  vpc_id                 = aws_vpc.Test_Linux_VPC.id
  cidr_block             = "10.0.1.0/24"
  availability_zone      = "eu-central-1a"

  tags = {
    Name                 = "Test_Public_Subnet"
  }
}

# Create private Subnet
resource "aws_subnet" "test_private_subnet" {
  vpc_id                 = aws_vpc.Test_Linux_VPC.id
  cidr_block             = "10.0.2.0/24"
  availability_zone      = "eu-central-1a"

  tags = {
    Name                 = "Test_Private_Subnet"
  }
}

# Create a new test route table for the public subnet and associate it with the VPC
resource "aws_route_table" "test_public_route_table" {
  vpc_id                 = aws_vpc.Test_Linux_VPC.id
}

# Create a new test route table association
resource "aws_route_table_association" "test_public_route_table_association" {
  subnet_id                 = aws_subnet.test_public_subnet.id
  route_table_id            = aws_route_table.test_public_route_table.id
}

# Create a VPC Internet Gateway
resource "aws_internet_gateway" "test_gateway" {
  vpc_id                 = aws_vpc.Test_Linux_VPC.id
}

# Add a default route to the internet gateway for the test public route table
resource "aws_route" "test_public_internet_access" {
  route_table_id         = aws_route_table.test_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.test_gateway.id
}

# Create public SG
resource "aws_security_group" "allow_ssh" {
  vpc_id                 = aws_vpc.Test_Linux_VPC.id
  name                   = "allow_ssh"
  description            = "Allow SSH inbound traffic"

  ingress {
    description          = "SSH from VPC"
    from_port            = 22
    to_port              = 22
    protocol             = "tcp"
    cidr_blocks          = ["0.0.0.0/0"]
  }

  egress {
    from_port            = 0
    to_port              = 0
    protocol             = "-1"
    cidr_blocks          = ["0.0.0.0/0"]
    ipv6_cidr_blocks     = ["::/0"]
  }

  tags = {
    Name                 = "allow_ssh"
  }
}

# Create private SG
resource "aws_security_group" "allow_private_docker" {
  vpc_id                 = aws_vpc.Test_Linux_VPC.id
  name                   = "allow_private_docker"
  description            = "Allow Docker inbound traffic"

  ingress {
    description          = "2376 tcp from VPC"
    from_port            = 2376
    to_port              = 2376
    protocol             = "tcp"
    cidr_blocks          = [aws_vpc.Test_Linux_VPC.cidr_block]
  }

  ingress {
    description          = "7946 tcp from VPC"
    from_port            = 7946
    to_port              = 7946
    protocol             = "tcp"
    cidr_blocks          = [aws_vpc.Test_Linux_VPC.cidr_block]
  }

  ingress {
    description          = "7946 udp from VPC"
    from_port            = 7946
    to_port              = 7946
    protocol             = "udp"
    cidr_blocks          = [aws_vpc.Test_Linux_VPC.cidr_block]
  }

  ingress {
    description          = "4789 udp from VPC"
    from_port            = 4789
    to_port              = 4789
    protocol             = "udp"
    cidr_blocks          = [aws_vpc.Test_Linux_VPC.cidr_block]
  }

  egress {
    from_port            = 0
    to_port              = 0
    protocol             = "-1"
    cidr_blocks          = ["0.0.0.0/0"]
    ipv6_cidr_blocks     = ["::/0"]
  }

  tags = {
    Name                 = "allow_private_Docker"
  }
}

# Create public NIC
resource "aws_network_interface" "public_nic" {
  subnet_id              = aws_subnet.test_public_subnet.id
  private_ips            = ["10.0.1.50"]
  security_groups        = [aws_security_group.allow_ssh.id]
  source_dest_check      = false
}

# Assign an Internet IP address to the public NIC
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.public_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.test_gateway]
}

# Create private NIC
resource "aws_network_interface" "private_nic" {
  subnet_id            = aws_subnet.test_private_subnet.id
  private_ips          = ["10.0.2.50"]
  security_groups      = [aws_security_group.allow_private_docker.id]
}

# Create IAM role
resource "aws_iam_role" "prometheus_role" {
  name                   = "prometheus_role"

  assume_role_policy     = jsonencode({
    Version              = "2012-10-17",
    Statement            = [
      {
        Effect             = "Allow",
        Principal          = {
          Service            = "ec2.amazonaws.com"
        },
        Action             = "sts:AssumeRole"
      }
    ]
  })
}

# Create IAM policy
resource "aws_iam_policy" "test_bucket_put_policy" {
  policy                 = jsonencode({
    Version                = "2012-10-17",
    Statement              = [
      {
        Effect               = "Allow",
        Action               = "s3:PutObject",
        Resource             = "arn:aws:s3:::test-bucket/some/path/*"
      }
    ]
  })

  name                   = "test_bucket_put_policy"
}

# Attach IAM policy to IAM role
resource "aws_iam_role_policy_attachment" "prometheus_attachment" {
  policy_arn             = aws_iam_policy.test_bucket_put_policy.arn
  role                   = aws_iam_role.prometheus_role.name
}

# Generate RSA key
resource "tls_private_key" "oskey" {
  algorithm              = "RSA"
  rsa_bits               = 4096
}

# Create local file with the generated key
resource "local_file" "myterrakey" {
  content                = tls_private_key.oskey.private_key_pem
  filename               = "myterrakey.pem"
  file_permission        = "0600"
}

# Upload the key to AWS
resource "aws_key_pair" "key121" {
  key_name               = "myterrakey"
  public_key             = tls_private_key.oskey.public_key_openssh
}

# Create a new instance profile with the IAM role
resource "aws_iam_instance_profile" "test_instance_profile" {
  name = "test-instance-profile"
  role = aws_iam_role.prometheus_role.name
}

# Create EC2 test instance
resource "aws_instance" "Test_Linux_Server" {
  ami                    = "ami-0cc29ffa555d90047"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.key121.key_name
  availability_zone      = "eu-central-1a"
  iam_instance_profile   = aws_iam_instance_profile.test_instance_profile.name

  provisioner "file" {
    source               = "playbook.yaml"
    destination          = "/tmp/playbook.yaml"
  }

  provisioner "file" {
    source               = "install.sh"
    destination          = "/tmp/install.sh"
  }

  provisioner "remote-exec" {
    inline               = [
      "chmod +x /tmp/install.sh",
      "/tmp/install.sh"
    ]
  }

# Add public nic
  network_interface {
    device_index         = 0
	network_interface_id = "${aws_network_interface.public_nic.id}"
  }
  
# Add private nic
  network_interface {
    device_index         = 1
	network_interface_id = "${aws_network_interface.private_nic.id}"
  }

  connection {
    type                 = "ssh"
    user                 = "ubuntu"
    private_key          = tls_private_key.oskey.private_key_pem
    host                 = aws_instance.Test_Linux_Server.public_ip
  }

  tags = {
    Name                 = "Test_Linux_Server"
  }
}

output "server_private_ip" {
  value                  = aws_instance.Test_Linux_Server.private_ip
}

output "server_public_ip" {
  value                  = aws_instance.Test_Linux_Server.public_ip
}

#output "nic_1" {
#  value                  = aws_network_interface.public_nic
#}

#output "nic_2" {
#  value                  = aws_network_interface.private_nic
#}

output "server_id" {
  value                  = aws_instance.Test_Linux_Server.id
}