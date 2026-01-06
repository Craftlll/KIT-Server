FROM rocker/r-ver:4.3.2

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libhdf5-dev \
    libsodium-dev \
    libgit2-dev \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 安装必要的 R 包（分步安装以便调试）
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org/')"

# 安装基础包
RUN R -e "install.packages(c('yaml', 'jsonlite', 'later', 'future'), repos='https://cloud.r-project.org/')"

# 安装 HTTP 相关包
RUN R -e "install.packages(c('httr', 'sodium'), repos='https://cloud.r-project.org/')"

# 安装数据处理包
RUN R -e "install.packages(c('dplyr', 'ggplot2'), repos='https://cloud.r-project.org/')"

# 安装 Bioconductor 和 rhdf5
RUN R -e "install.packages('BiocManager', repos='https://cloud.r-project.org/')" && \
    R -e "BiocManager::install('rhdf5', ask=FALSE)"

# 安装 plumber
RUN R -e "install.packages(c('plumber', 'futile.logger'), repos='https://cloud.r-project.org/')"

# 复制应用代码
COPY . .

# 暴露端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 启动命令 - 使用 Nacos 集成版本
CMD ["Rscript", "run_with_nacos.R"]
