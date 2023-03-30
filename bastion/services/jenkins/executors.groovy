import jenkins.model.*
Jenkins.instance.setNumExecutors(8) // Recommended to not run builds on the built-in node