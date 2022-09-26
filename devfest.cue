package devfest

import (
    "dagger.io/dagger"
    "universe.dagger.io/docker"
    "strings"
)

dagger.#Plan & {
    client: {
      filesystem: {
          "./site": read: contents: dagger.#FS
          //"a.txt": write: contents: actions.deploy.res.contents
      }
      
      env: {
        GITHUB_USER: string
        GITHUB_TOKEN: dagger.#Secret
        KUBECONFIG: string
      }

      commands: kubeconfig: {
			  name: "cat"
	  		args: ["\(env.KUBECONFIG)"]
		  	stdout: dagger.#Secret
	  	}
    }

    actions: {
      // Build de l'image
      build: docker.#Dockerfile & {
        // This is the Dockerfile context
        source: client.filesystem."./site".read.contents
        platforms: ["linux/arm64", "linux/amd64"]
      }  
      // Push de l'image
      push: docker.#Push & {
        auth: {
          username: client.env.GITHUB_USER
          secret: client.env.GITHUB_TOKEN
        }
        image: build.output // Dépendance avec action build cette acction se déclenchera à la suite de `build`
        dest: "ghcr.io/herveleclerc/devfestdemo:1.0.0"
      }

      // Génération des manifests de l'application grace au CUE templating
      appmanifest: #AppManifest & {
        name:  "devfest"
        image: strings.Trim(actions.push.result,"\n")
      }

      deploy: {

        // Conteneur tool
        pull: docker.#Pull & {
          source: "lachlanevenson/k8s-kubectl"
        }

        // Configuration et lancement
			  run: docker.#Run & {
          env: {
            KUBECONFIG: "/tmp/.kube/config"
          }
			  	input: pull.output
			  	mounts: {
            kubeconfig: {
			  		  dest:     "/tmp/.kube/config"
			  		  contents: client.commands.kubeconfig.stdout
              type:     "secret"
            }
            manifest: {
               dest: "/tmp/manifest.yaml"
               contents: actions.appmanifest.manifest
               type: "file"
            }
			  	}
			    command: {
            name: "apply"
            flags: {
              "-f": "/tmp/manifest.yaml"
            }
          }		
			  }
			  //res: core.#ReadFile & {
			  //	input: run.output
			  //	path:  "/tmp/a.txt"
			  //}
		}
      
  }
}
