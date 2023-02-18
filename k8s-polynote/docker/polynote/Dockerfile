FROM polynote/polynote:0.5.0-2.12

WORKDIR /opt

USER root

COPY install_spark.sh .
RUN ./install_spark.sh

ENV SPARK_HOME="/opt/spark"
ENV HADOOP_HOME="/opt/hadoop-3.2.0"
ENV PATH="$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin"

# switch to non-root user
USER ${NB_USER}
