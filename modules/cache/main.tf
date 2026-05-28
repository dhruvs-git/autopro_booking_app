# ELASTICACHE SUBNET GROUP
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-redis-subnet-group"
  subnet_ids = var.private_db_subnet_ids

  tags = {
    Name = "${var.name_prefix}-redis-subnet-group"
  }
}



# ELASTICACHE REDIS CLUSTER
# Single node cluster — Free Tier eligible.
# In production: num_cache_nodes = 2+ with automatic failover enabled.
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.name_prefix}-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t3.micro"    # Free Tier eligible
  num_cache_nodes      = 1                   # always 1 for Redis single node
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.redis_sg_id]

  # Snapshots (Redis only)
  snapshot_retention_limit = 1       # days to keep snapshots
  snapshot_window          = "05:00-06:00"

  apply_immediately = true

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}