# VPC 
resource "aws_vpc" "main" {
  cidr_block       = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true


  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}


# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-subnet${count.index + 1}"
  }
}


# Private App Subnets
resource "aws_subnet" "private_app" {
  count = length(var.private_app_subnet_cidrs)

  vpc_id = aws_vpc.main.id
  cidr_block = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-app-subnet${count.index + 1}"
  }
}


# Private DB Subnets
resource "aws_subnet" "private_db" {
  count = length(var.private_db_subnet_cidrs)

  vpc_id = aws_vpc.main.id
  cidr_block = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-db-subnet${count.index + 1}"
  }
}


# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}


#Elastic IP for NAT gateway
resource "aws_eip" "eip_nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }
}


# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.eip_nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.name_prefix}-nat-gw"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


#Private Route table APP
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-private-app-rt"
  }
}

resource "aws_route_table_association" "private_app" {
  count = length(aws_subnet.private_app)

  subnet_id = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}


#Private Route table DB
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-private-db-rt"
  }
}

resource "aws_route_table_association" "private_db" {
  count = length(aws_subnet.private_db)

  subnet_id = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

