# Retrieve the existing VPC
data "aws_vpc" "existing_vpc" {
  id = "vpc-076c009696d0b84e6"
}

###create new prefix CIDR on vpn
resource "aws_vpc_ipv4_cidr_block_association" "new_cidr" {
  vpc_id     = data.aws_vpc.existing_vpc.id
  cidr_block = "172.16.0.0/16"
}

resource "aws_subnet" "web" {
  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = "172.16.38.0/23"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "web"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.new_cidr]
}

resource "aws_subnet" "web_2" {
  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = "172.16.40.0/23"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "web_2"
  }
  depends_on = [aws_vpc_ipv4_cidr_block_association.new_cidr]
}


# Create a security group for the EFS
resource "aws_security_group" "allow_efs" {
  name        = "allow_efs"
  description = "Allow inbound traffic"
  vpc_id      = data.aws_vpc.existing_vpc.id

  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["172.16.38.0/23"]
  }
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["172.16.40.0/23"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.16.38.0/23"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.16.40.0/23"]
  }
}
# Create the EFS filesystem
resource "aws_efs_file_system" "html" {
  creation_token   = "efs-html"
  performance_mode = "generalPurpose"
}
# Create the mount target
resource "aws_efs_mount_target" "html" {
  file_system_id  = aws_efs_file_system.html.id
  subnet_id       = aws_subnet.web.id
  security_groups = [aws_security_group.allow_efs.id]
}
# Create the mount target
resource "aws_efs_mount_target" "html_2" {
  file_system_id  = aws_efs_file_system.html.id
  subnet_id       = aws_subnet.web_2.id
  security_groups = [aws_security_group.allow_efs.id]
}

# Create an ELB listener
resource "aws_lb_listener" "web_lb_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.web_lb_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "web_lb_tg" {
  name        = "web-lb-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.existing_vpc.id
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/"
  }
}

# Create an ELB
resource "aws_lb" "web_lb" {
  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_lb.id]
  subnets            = [aws_subnet.web.id, aws_subnet.web_2.id]
}

# Create a security group for the ELB
resource "aws_security_group" "allow_lb" {
  name        = "allow_lb"
  description = "Allow inbound traffic"
  vpc_id      = data.aws_vpc.existing_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group_attachment" "web_lb_tg_attachment" {
  target_group_arn = aws_lb_target_group.web_lb_tg.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_lb_tg_attachment2" {
  target_group_arn = aws_lb_target_group.web_lb_tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

##create a ec2 on one zone
resource "aws_instance" "web" {
  ami             = "ami-0a695f0d95cefc163"
  instance_type   = "t2.micro"
  key_name        = "aws-developer-key"
  security_groups = [aws_security_group.allow_ssh.id]
  subnet_id       = aws_subnet.web.id
  tags = {
    Name = "web-server"
  }
  depends_on = [aws_efs_mount_target.html]
  user_data  = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y apache2
              systemctl enable apache2
              systemctl start apache2
              apt-get install -y nfs-common
              mkdir -p /var/www/html
              mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_efs_file_system.html.dns_name}:/ /var/www/html
              echo "<h1>Web Server</h1>" > /var/www/html/index.html
              EOF
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = aws_instance.web.public_ip
  }
}
##create a ec2 on one zone 2
resource "aws_instance" "web2" {
  ami             = "ami-0a695f0d95cefc163"
  instance_type   = "t2.micro"
  key_name        = "aws-developer-key"
  security_groups = [aws_security_group.allow_ssh.id]
  subnet_id       = aws_subnet.web_2.id
  tags = {
    Name = "web-server2"
  }
  ## depends_on the EFS file system
  depends_on = [aws_efs_mount_target.html_2]
  user_data  = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y apache2
              systemctl enable apache2
              systemctl start apache2
              apt-get install -y nfs-common
              mkdir -p /var/www/html
              mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_efs_file_system.html.dns_name}:/ /var/www/html
              echo "<h1>Web Server</h1>" > /var/www/html/index.html
              EOF
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = aws_instance.web2.public_ip
  }
}
##use ssh key save in aws
resource "aws_key_pair" "aws-ec2-terraform" {
  key_name   = "aws-developer-key"
  public_key = file("~/.ssh/id_rsa.pub")
}
##create a security group
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow ssh inbound traffic"
  vpc_id      = "vpc-076c009696d0b84e6"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

