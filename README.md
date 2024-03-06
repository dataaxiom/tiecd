![alt text](https://raw.githubusercontent.com/dataaxiom/tiecd/main/docs/tiecd.png)

## Pipeline tools for cloud deployments

Tiecd is a collection of standard tools for building and deploying applications into kubernetes environments. It's bundled as a containerized solution itself, designed to run directly in CICD pipelines.  It ties together the standard tools for kubernetes deployments and provides a higher level abstraction DSL (domain specific language) around them.

Typical applications directly call standard tools directly from their pipeline scripts. Tiecd instead takes a different approach, the developer/operator describes the application via a DSL syntax in a tie.yml file (the 'what' of the application deployment). Tiecd then implements the 'how' by processing the resources in the DSL file and applying them to the deployment target. The DSL describes such things as the target environments to deploy to, image registries in use, applciations to deploy, files/secrets to  mount and additional helm charts to deploy. Tiecd process the DSL file and calls the underlying command tools and implements best practices around the deployment. It simplifies the deployment process.

Tiecd takes the gitops approach to CICD deployments. Running in a pipeline triggered from a git commit tiecd expresses the contents of the git repository to the target deployment platform continuiously. It takes a more active syncronous approach rather then some alternative CICD approaches which take polling asynchronous approaches.

## Core Features

* Multiple pass variable expansion
* Helm suport
* Template support
* Pre/Post hooks for complex deployments

## Embedded Tools

Current tools embedded in the tiecd image include:
* kubectl/oc (cluster control/deployment)
* skopeo (image copy/movement)
* helm (kubernetes deployments)
* git, ssh/scp, jq (assorted tools)


## Runtime Modes
### Deployment

There are three broad appoaches for deployments, directly providing the deployment artifacts, having tiecd generate the deployment artifacts and using helm.


##### Provide Deployment Artifacts

```yaml
environments:
- apiConfig: ${KUBE_CONFIG_FILE}

apps:
- name: webapp
  manifests:
  - webapp.yml
```
The above tie.yml file when executed will apply the webapp.yml file to the cluster specified in the environments section. It will call kubectl commands to apply the objects in the file and wait if necessary for their rollout. The webapp.yml would contain the kubernetes objects to be applied.

##### Generate Deployment Artifacts - TODO
```yaml
environments:
- apiConfig: ${KUBE_CONFIG_FILE}

apps:
- name: webapp
  image:
    version: 1.0.1
    type: springboot
  mountFiles:
  - file: config/application.yml
    mount: /deployments/config/application.yml
```
Tiecd can generate deployment files (much like helm) for standard application such as java,springboot,node and dotnet. In the above sample the image "webapp" is deployed into kubernetes cluster using standard conventions about what a springboot application should be deployed as. It additionally wires in the file config/application.yml file into the remote deployment. For a kubernetes deployment this would resulting in Deployment and Configmap definitions being generated and applied to the cluster.

To execute the tiecd process on a tie.xml file, the tiecd command is called in the pipeline:
```
tiecd deploy
```

##### Helm Deployments
Helm carts can been described with associated values files direclty in a git repo. Tiecd will then execute these charts upon the cluster calling the helm commands and assocated kubectl commands. In conjuction with the standard tiecd funcionality it can provide a more complete helm deployment solution, providng for image moving, non helm artifacts (config/secrets/templates) and value expansion. 
```yaml
apps:
- name: grafana
  mountFiles:
  - file: grafana.ini
  - file: dashboard/jvm.json
  secrets:
  - prometheus-ds.yml
  helmChart:
    url: "oci://registry-1.docker.io/bitnamicharts/grafana"
    version: 9.0.3
    values:
    - grafana-values.yml
  manifests:
  - route.yaml

```
The above helm chart makes use of additional resources. It deploys those mount files and secret, which are then configured via the helm values files. Aditionaly, a custom openshift route object is applied as an example.


### Image Building - TODO

Tiecd can build standard application images out of the box, using a dockerless build process. No Dockerfile or privledged docker runners required. The approach tiecd takes is to use standard runtime images as the base image and then layers on the application bits as an additional image layer. 

For example, to build a springboot application define the app in a tie.yml file:

```yaml
apps:
- name: helloworld
  image:
    type: springboot
  artifacts:
  - groupId: hello.world.app
    artifactId: helloWorldApp
    version: 1.0.0  
```

then building the image can be done via:
```
tiecd build
```

