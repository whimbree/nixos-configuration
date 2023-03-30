FROM jenkins/jenkins:lts-jdk11
COPY --chown=jenkins:jenkins executors.groovy /usr/share/jenkins/ref/init.groovy.d/executors.groovy

USER root
RUN usermod -aG docker jenkins
 
USER jenkins