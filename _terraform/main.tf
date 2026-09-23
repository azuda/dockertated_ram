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

variable "az" {
  default = "us-west-2a"
}

variable "instance_enabled" {
  description = "Set to false to terminate the mc_server instance while retaining the EBS volume and EIP."
  type        = bool
  default     = true
}

data "aws_key_pair" "mc_key" {
  key_name = "aws-mcvm"
}

data "aws_security_group" "mc_sg" {
  id = "sg-0ca4ed51a0ca93c10"
}

resource "aws_instance" "mc_server" {
  count = var.instance_enabled ? 1 : 0

  availability_zone            = var.az
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
              mkdir -p /usr/local/lib/docker/cli-plugins
              curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 -o /usr/local/lib/docker/cli-plugins/docker-compose
              chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

              # Wait for the data volume to attach (NVMe naming — required on Nitro instances like t4g)
              while [ ! -e /dev/nvme1n1 ]; do sleep 1; done

              # Only format if it has no filesystem yet (first-ever boot)
              if ! blkid /dev/nvme1n1; then
                mkfs -t ext4 /dev/nvme1n1
              fi

              mkdir -p /home/ec2-user/mc-server
              mount /dev/nvme1n1 /home/ec2-user/mc-server
              echo "/dev/nvme1n1 /home/ec2-user/mc-server ext4 defaults,nofail 0 2" >> /etc/fstab

              cat > /home/ec2-user/mc-server/docker-compose.yaml <<'COMPOSE_EOF'
              ${file("${path.module}/docker-compose.yaml")}
              COMPOSE_EOF
              chown -R ec2-user:ec2-user /home/ec2-user/mc-server

              cd /home/ec2-user/mc-server
              docker compose up -d
              EOF

  tags = {
    Name = "minecraft-server"
  }
}

resource "aws_eip" "mc_eip" {
  domain = "vpc"

  tags = {
    Name = "minecraft-server-eip"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_eip_association" "mc_eip_assoc" {
  count = var.instance_enabled ? 1 : 0

  instance_id   = aws_instance.mc_server[0].id
  allocation_id = aws_eip.mc_eip.id
}

resource "aws_cloudwatch_metric_alarm" "mc_idle_shutdown" {
  count = var.instance_enabled ? 1 : 0

  alarm_name          = "mc-server-idle-shutdown"
  alarm_description   = "Terminates the mc_server instance after ~1 hour of no player traffic."
  namespace           = "AWS/EC2"
  metric_name         = "NetworkOut"
  statistic           = "Average"
  period              = 300    # 5 minutes
  evaluation_periods  = 12     # 12 * 5min = 1 hour
  threshold           = 100000 # bytes; idle background traffic should stay under this
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.mc_server[0].id
  }

  alarm_actions = ["arn:aws:automate:us-west-2:ec2:terminate"]
}

resource "aws_ebs_volume" "mc_data" {
  availability_zone = var.az
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
  count = var.instance_enabled ? 1 : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mc_data.id
  instance_id = aws_instance.mc_server[0].id
}
