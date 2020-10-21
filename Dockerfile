# https://github.com/rocker-org/binder
# https://blog.csdn.net/weixin_41164688/article/details/101067324

FROM shichenxie/scorecard:latest

# https://www.cnblogs.com/nihaorz/p/12036344.html
RUN mv /etc/apt/sources.list /etc/apt/sources.list.bak
COPY sources.list /etc/apt/sources.list

# install nodejs ---------------------------------------------------------#
RUN apt-get update && \
    apt-get -y install curl cmake && \
    curl -sL https://deb.nodesource.com/setup_10.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get -y install nodejs && \
    rm -rf /var/lib/apt/lists/*

# install anaconda3 ------------------------------------------------------#
# https://hub.docker.com/r/continuumio/anaconda3/dockerfile
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing && apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    git mercurial subversion

RUN wget --quiet https://mirrors.tuna.tsinghua.edu.cn/anaconda/archive/Anaconda3-5.3.0-Linux-x86_64.sh -O ~/anaconda.sh && \
    /bin/bash ~/anaconda.sh -b -p /opt/conda && \
    rm ~/anaconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc

RUN apt-get install -y curl grep sed dpkg && \
    TINI_VERSION=`curl https://github.com/krallin/tini/releases/latest | grep -o "/v.*\"" | sed 's:^..\(.*\).$:\1:'` && \
    curl -L "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini_${TINI_VERSION}.deb" > tini.deb && \
    dpkg -i tini.deb && \
    rm tini.deb && \
    apt-get clean

ENTRYPOINT [ "/usr/bin/tini", "--" ]
CMD [ "/bin/bash" ]

# install jupyterhub -----------------------------------------------------#
ENV CONDA_DIR /opt/conda

RUN conda install --no-deps pip
RUN python3 -m venv ${CONDA_DIR} && \
    pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple --no-cache-dir \
         dlib xgboost sklearn2pmml sklearn_pandas \
         jupyterhub \
         jupyter-rsession-proxy \
         jupyter_nbextensions_configurator \
         dockerspawner
RUN npm install -g configurable-http-proxy

# jupyterhub_config
RUN jupyterhub --generate-config
    
# authenticator ----------------------------------------------------------#
# native authenticator
# https://native-authenticator.readthedocs.io/en/latest/quickstart.html
# RUN git clone https://github.com/jupyterhub/nativeauthenticator.git /temp 
ADD nativeauthenticator /tmp/nativeauthenticator
RUN mv /tmp/nativeauthenticator ${CONDA_DIR}/bin/nativeauthenticator && \
    pip3 install -e ${CONDA_DIR}/bin/nativeauthenticator --no-cache-dir 

# R path -----------------------------------------------------------------#
RUN echo "PATH=${PATH}" >> /usr/local/lib/R/etc/Renviron && \
    echo 'SPARK_HOME = "/opt/spark/spark-2.2.0-bin-hadoop2.7"' >> /usr/local/lib/R/etc/Renviron && \
    echo 'SPARK_HOME_VERSION = "2.2.0"' >> /usr/local/lib/R/etc/Renviron

ENV LD_LIBRARY_PATH /usr/local/lib/R/lib

RUN R --quiet -e "install.packages('IRkernel', repos = 'https://mirrors.tuna.tsinghua.edu.cn/CRAN/')" && \
    R --quiet -e "IRkernel::installspec(user=FALSE)"#, prefix='${CONDA_DIR}/bin' && \
    R --quiet -e "install.packages(c('png', 'reticulate', 'odbc', 'sparklyr', 'blastula', 'cronR'), repos = 'https://mirrors.tuna.tsinghua.edu.cn/CRAN/')" && \
    rm -rf /tmp/*

RUN chmod -R 777 /usr/local/lib/R

# Install jdk 8 ----------------------------------------------------------#
RUN apt-get -y install software-properties-common && \
    apt-add-repository 'deb http://security.debian.org/debian-security stretch/updates main' && \
    apt-get update && \
    apt-get -y install openjdk-8-jdk && \
    update-java-alternatives -s java-1.8.0-openjdk-amd64 && \
    rm -rf /var/lib/apt/lists/*

# transwarp odbc driver --------------------------------------------------#
# http://support.transwarp.cn/t/odbc-jdbc/477
RUN apt-get update --fix-missing && \
    apt-get -y install alien && \
    apt-get -y install apt-utils sasl2-bin libsasl2-dev libsasl2-modules && \
    rm -rf /var/lib/apt/lists/*

COPY inceptor-connector-odbc-6.0.0-1.el6.x86_64.rpm  / 
RUN alien --install inceptor-connector-odbc-6.0.0-1.el6.x86_64.rpm --scripts
RUN cp -a /usr/local/inceptor/. /etc/ && \
    rm inceptor-connector-odbc-6.0.0-1.el6.x86_64.rpm

# install Oracle Instant Client
ADD oracle-instantclient*.rpm /tmp/
RUN  alien --install /tmp/oracle-instantclient*.rpm --scripts && \
     rm -f /tmp/oracle-instantclient*.rpm

# spark r/py package 
COPY spark-2.2.0-bin-hadoop2.7.tgz / 
RUN mkdir -p /opt/spark
RUN R --quiet -e "options(spark.install.dir = '/opt/spark'); sparklyr::spark_install_tar('spark-2.2.0-bin-hadoop2.7.tgz'); install.packages('RPostgres', repos = 'https://mirrors.tuna.tsinghua.edu.cn/CRAN/')" && \
    rm spark-2.2.0-bin-hadoop2.7.tgz && \
    rm -rf /tmp/*

RUN python3 -m venv ${CONDA_DIR} && \
    pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple --no-cache-dir \
         pyspark sqlalchemy cx_Oracle pandas --force

# jupyterhub config ------------------------------------------------------#
COPY jupyterhub_config.py /
CMD jupyterhub -f jupyterhub_config.py

# Setup application
RUN useradd --create-home xieshichen

EXPOSE 8000
CMD jupyterhub


# setting ----------------------------------------------------------------#
# docker build -t dstudio .
# mkdir -p $HOME/docker/dstudio
# docker run -d -p 8000:8000 -v $HOME/docker/dstudio:/home --restart=always --name dstudio dstudio

# # after launch rstudio in browser, otherwise rstudio cant be entered by multiple uers
# docker exec -it dstudio bash
# chmod -R 777 /tmp/rstudio-server/secure-cookie-key

# Authorization Area
# http://localhost:8000/hub/authorize
# http://localhost:8000/hub/change-password

# useradd --create-home xieshichen
# passwd xieshichen

# adduser xieshichen # passwd xieshichen
# adduser xieshichen ds

# docker save dstudio > dstudio.tar
# docker load --input dstudio.tar



# setting R environment config
# https://rviews.rstudio.com/2017/04/19/r-for-enterprise-understanding-r-s-startup/
# Sys.getenv('SPARK_HOME')
# usethis::edit_r_environ() 
# Sys.getenv('R_HOME') # /usr/local/lib/R
# R_HOME/etc/.Renviron
