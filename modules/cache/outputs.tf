output "redis_endpoint" {
  description = "redis cluster endpoint - flask connects here for caching"
  value = aws_elasticache_cluster.main.cache_nodes[0].address
}