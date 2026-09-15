terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

data "aws_key_pair" "mc_key" {
  key_name = "aws-mcvm"
}

data "aws_security_group" "mc_sg" {
  id = "sg-0ca4ed51a0ca93c10"
}

resource "aws_instance" "mc_server" {
  ami                          = "ami-0c9da9b2b7758f931"
  instance_type                = "t4g.xlarge"
  key_name                     = data.aws_key_pair.mc_key.key_name
  vpc_security_group_ids       = [data.aws_security_group.mc_sg.id]
  user_data_replace_on_change  = true

  root_block_device {
    delete_on_termination = true
    volume_size           = 50 # GB
    volume_type           = "gp3"

    tags = {
      Name = "mcvm-volume"
    }
  }

  # first time setup
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ec2-user
              curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              # Wait for the data volume to attach
              while [ ! -e /dev/xvdf ]; do sleep 1; done

              # Only format if it has no filesystem yet (first-ever boot)
              if ! blkid /dev/xvdf; then
                mkfs -t ext4 /dev/xvdf
              fi

              mkdir -p /home/ec2-user/mc-server
              mount /dev/xvdf /home/ec2-user/mc-server
              echo "/dev/xvdf /home/ec2-user/mc-server ext4 defaults,nofail 0 2" >> /etc/fstab

              cat > /home/ec2-user/mc-server/docker-compose.yaml <<'COMPOSE_EOF'
              ${file("${path.module}/docker-compose.yaml")}
              COMPOSE_EOF
              chown -R ec2-user:ec2-user /home/ec2-user/mc-server

              cd /home/ec2-user/mc-server
              docker-compose up -d
              EOF

  tags = {
    Name = "minecraft-server"
  }
}

resource "aws_eip" "mc_eip" {
  instance = aws_instance.mc_server.id
  domain   = "vpc"

  tags = {
    Name = "minecraft-server-eip"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ebs_volume" "mc_data" {
  availability_zone = aws_instance.mc_server.availability_zone
  size              = 50 # GB
  type              = "gp3"

  tags = {
    Name = "minecraft-world-data"
  }

  lifecycle {
    prevent_destroy = true  # safety net against accidental `terraform destroy`
  }
}

resource "aws_volume_attachment" "mc_data_attach" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mc_data.id
  instance_id = aws_instance.mc_server.id
}
