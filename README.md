# Introduction

Template for running Strapi and Gatsby as serverless instances with Azure container Instances (ACI) while still benefiting from Live Preview feature.
The project is divived in four parts:  
- **Strapi v4** docker image wrapped in a **node.js** application.
- **Gatsby v4** docker image containing the code of our static web application and run with **gatsby develop**. This is basically our staging environment.
- Powershell Azure function starting/stopping the ACI (Http Trigger)
- Terraform script 

The flow is simple:
- When a users/editors needs to access **Strapi** and **Gatsby**, they send a request to an **Azure function**.  
- The Azure function does the work of **starting** ACIs for Strapi and Gatsby and returns an html code that will query Azure periodically for the status of the ACIs (Pending, running, Stopped..)  
- Once the ACI is ready and running, a button appears on the page that indicates to the user that Strapi is ready.
- The instances stays up for as long as the user needs it, and only once Strapi remains idle for a specific amount of time (default value set to **30 min**), the node.js application running Strapi sends a request to an Azure function that takes care of **stopping** the ACI.

As Strapi does not handle ssl, a **reverse proxy** is deployed in front of Strapi (**Caddy** web server) as a sidecar container.
Same thing is done for Gatsby.

> **NB**: In a production scenario, this solution needs to be complemented by adding a static web app built for production (or any other way you would normally deploy Gatsby online).

# Prerequisites

- Prior knowledge of the following are recommended:
- Strapi,
- Gatsby, 
- Azure platform, 
- Terraform.

The deployment without Terraform is possible as well, but not covered here.  

In order to start off, you will need to have the following:
- Terraform installed locally
- An Azure subscription with admin rights
- A service principal with Contributor role (required for the Azure functions)
- A container registry, preferably private (I use Azure Container Registry (ACR) in this template but any other should work as well)
- Node.js v12 or v14 (preferred for Strapi v4)  
- npm v6 or yarn
- Docker
- Powershell (including az cli)
- DB Browser (SQLite)

# Installation

- Clone git repository

## Strapi

- Open a command line in the root of the solution:
```
cd strapi-aci
yarn install
yarn build
yarn develop
```

After that an SQLite file should be present in ```./strapi-aci/tmp/``` folder.
Open the file with **DB Browser (SQLite)** and run the pragma command:
> PRAGMA journal_mode=WAL;  

This step will run the SQLite instance in **WAL** mode (Write Ahead Logging) and is **necessary** in order to run SQLite on an Azure File Share with Strapi in ACI.

**NB**: Make sure that your strapi instance is working properly after that. If that works you should see that the ```tmp``` folder now contains 3 different files when Strapi performs read/write operations.

## Gatsby

- Open a command line in the root of the solution:
```
cd gatsby-swa
npm install
```

# Variable edits

First of all, edit the data in the following files so they relate to your context/environment:
- ```./terraform/terraform.tfvars```
- ```./strapi-aci/.env``` (set proper keys for ```APP_KEYS, API_TOKEN_SALT, ADMIN_JWT_SECRET``` and ```JWT_SECRET``` based on .env.example)
- ```./strapi-aci/build.dev.ps1```
- ```./strapi-aci/build.prod.ps1```
- ```./strapi-aci/run.dev.ps1```
- ```./strapi-aci/config/middlewares.js``` (to allow your function app query Strapi endpoint)
- ```./gatsby-swa/build.dev.ps1```
- ```./gatsby-swa/build.prod.ps1```
- ```./gatsby-swa/run.dev.ps1```

# Docker image

Once this is done, and the prerequite above fulfilled, you can now build your docker images for Strapi and Gatsby via the following PowerShell scripts:
- build.dev.ps1: for local development
- build.prod.ps1: for storing in your container registry.

**NB**: The PowerShell scripts assume that you are using ACR as container registry, but this is easily adaptable to another provider.  

# Deployment

Once our images are built, you are now ready to deploy!

```
cd ./terraform
terraform init
terraform plan -out=plan
terraform apply plan
```

After a few minutes, if everything went well, you should now have a resource group created with the following resources:
- Strapi Container Instance
- Gatsby Container Instance
- App Service Plan
- Function App
- Storage Account

You can then connect to your Storage Account, and copy/paste your local SQLite file (located in ```strapi-aci/tmp/data.db```) into the ```aci-strapi-db-prod``` file share (use Azure Storage Explorer, az cli or alternatively Azure ui).

That's it, you just deployed Strapi / Gatsby in a serverless way via ACI.

Finally, last operation is to deploy our Azure Function code to the Function App located in ```./azure-function``` folder. You can do this with VS Code with the ```Azure Functions``` extension or via Azure Function Core Tools cli, that is up to you.

Once this is done, you can now call your Azure function to start up the ACI, and you should be redirected within a couple of minutes to your newly created Strapi instance. 

# Working locally

You have the possibility to test your Strapi installation in a few different ways:
- using ```yarn develop``` to start Strapi in the conventional way on your local host
- using ```npm run start-node``` to start ```index.js``` which in turn starts Strapi as well.
- using ```Docker``` and your latest image built with ```Dockerfile.dev```. See ```run.dev.ps1``` to start a container in your respective environment.  

For Gatsby, almost the same applies.
- using ```gatsby develop``` to start gatsby in the conventional way for local development
- using ```Docker``` and your latest image built with ```Dockerfile.dev```. See ```run.dev.ps1``` to start a container in your respective environment.  

**NB**: I did not create a Docker compose in this repo to reverse proxy our Strapi docker container.

# Issues / Suggestions

Please file issues or suggestions on the issues page on github, or even better, submit a pull request. Feedback is always welcome!

# References

Thanks to Johan Gyger for his very useful article on how to set up a **Caddy web server** reverse proxy with ACI via Terraform : https://itnext.io/automatic-https-with-azure-container-instances-aci-4c4c8b03e8c9  
Thanks to Simen Daehlin for his article regarding **Docker with Strapi V4**: https://blog.dehlin.dev/docker-with-strapi-v4

# Publication

The following Medium is related to this GitHub repo.

# License
Copyright © 2015-present Clément Joye

MIT
