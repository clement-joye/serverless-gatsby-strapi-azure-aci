az login
az acr login --name <your_acr_name>

docker build -t <your_project_name>_strapi_aci:latest -f Dockerfile.prod .
docker tag <your_project_name>_strapi_aci:latest <your_acr_name>.azurecr.io/<your_project_name>_strapi_aci:latest
docker push <your_acr_name>.azurecr.io/<your_project_name>_strapi_aci:latest
