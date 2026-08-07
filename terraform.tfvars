project = "test-backend"
region  = "eu-north-1"

container_port    = 8080
health_check_path = "/actuator/health"
image_tag         = "v1.0.0"
spring_profile    = "prod"

# test-backend/CorsConfig.java /api/** ucun. Frontend yoxdursa deymeye ehtiyac yoxdur.
cors_allowed_origins = "http://localhost:5173"

task_cpu      = 512
task_memory   = 1024
desired_count = 2

# ../test-backend/Dockerfile curl qurur, ona gore true etmek olar.
# Ilk deploy-da false saxla - problem olsa sebebi daraltmaq asan olur.
cpu_architecture             = "X86_64"
enable_container_healthcheck = false

db_name              = "appdb"
db_username          = "appuser"
db_instance_class    = "db.t4g.micro"
db_allocated_storage = 20
db_multi_az          = false

# Bu hesab Free Tier planindadir: backup / storage autoscaling / Performance Insights
# bloklanir. Hesabi paid plan-a kecirende false et.
free_tier_account = true

# Yalniz major versiya -> RDS en son minor-u secir (hazirda 16.14)
db_engine_version = "16"

# Oyrenme/test ucun false (NAT Gateway ~$35/ay). ECS task-lar public subnet-de olur.
enable_nat_gateway = false
