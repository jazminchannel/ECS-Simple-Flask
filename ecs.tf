provider "aws" {
  region = "us-east-1" # Change to your desired region
}

# Define your ECS cluster
resource "aws_ecs_cluster" "flask_cluster" {
  name = "flask-app-cluster"
}

# # Check if IAM role for the ECS task exists, or create it
# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "ecsTaskExecutionRole"

#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "Service": "ecs-tasks.amazonaws.com"
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# EOF

#   lifecycle {
#     create_before_destroy = true
#     ignore_changes        = [name]
#   }
# }

# # Attach policies to the ECS task execution role
# resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
#   role       = data.aws_iam_role.ecs_task_execution_role
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# Use existing IAM role for ECS task execution
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

# Define the ECS task definition
resource "aws_ecs_task_definition" "flask_task" {
  family                   = "flask-task"
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "flask-app"
      image     = "329031661061.dkr.ecr.us-east-1.amazonaws.com/simple-flask-amd64:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
      environment = [
        {
          name  = "FLASK_ENV"
          value = "production"
        }
      ]
    }
  ])
}

data "aws_subnet" "selected_subnet" {
  id = "subnet-09493d1b295863b93" # Replace with your private subnet ID
}

# Create a security group for the ECS service
resource "aws_security_group" "ecs_service_sg" {
  name_prefix = "flask-app-sg"
  vpc_id      = data.aws_subnet.selected_subnet.vpc_id

  ingress {
    from_port   = 5000
    to_port     = 5000
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

# Define the ECS service
resource "aws_ecs_service" "flask_service" {
  name            = "flask-service"
  cluster         = aws_ecs_cluster.flask_cluster.id
  task_definition = aws_ecs_task_definition.flask_task.arn
  launch_type     = "EC2"

  network_configuration {
    subnets         = ["subnet-09493d1b295863b93"] # Replace with your VPC private subnet IDs
    security_groups = [aws_security_group.ecs_service_sg.id]
  }
  desired_count = 1
}

# Output the ECS cluster and service info
output "ecs_cluster_name" {
  value = aws_ecs_cluster.flask_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.flask_service.name
}

# Use existing IAM role for ECS instances
data "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile"
  role = data.aws_iam_role.ecs_instance_role.name
}


# Attach policies to the ECS instance role
resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = data.aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}


# Define a launch template for the ECS instances
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "ecs-launch-template"
  image_id      = "ami-0de53d8956e8dcf80" # Amazon ECS-optimized AMI (for us-east-1, change for other regions)
  instance_type = "t2.micro"
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.flask_cluster.name} >> /etc/ecs/ecs.config
curl -s http://169.254.169.254/latest/meta-data/instance-id
EOF
  )
}

# Create an Auto Scaling Group (ASG) for the ECS instances
resource "aws_autoscaling_group" "ecs_asg" {
  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  vpc_zone_identifier = ["subnet-09493d1b295863b93"] # Replace with your VPC private subnet IDs

  tag {
    key                 = "Name"
    value               = "ecs-instance"
    propagate_at_launch = true
  }
}

