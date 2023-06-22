process CALL_VARIANTS_NEW {
    container 'staphb/snippy:4.6.0-SC2'

    input:
    tuple val(taxa_cluster), val(samples), val(taxa), path(assemblies), path(fastq_1), path(fastq_2), val(cluster), val(status)

    output:
    tuple val(cluster_name), val(taxa_name), path(cluster_name), path("*.tar.gz"), path("core/core.*"), val(status), emit: snippy_results

    when:
    task.ext.when == null || task.ext.when

    shell:
    assembly_names = assemblies.name
    fwd_reads = fastq_1.name
    rev_reads = fastq_2.name
    taxa_name = taxa[0]
    cluster_name = cluster[0]
    '''
    # create .tsv of samples and their associated files
    echo !{samples} | tr -d '[] ' | tr ',' '\n' > s_col
    echo !{assembly_names} | tr -d '[] ' | tr ',' '\n' > a_col
    echo !{fwd_reads} | tr -d '[] ' | tr ',' '\n' > r1_col
    echo !{fwd_reads} | tr -d '[] ' | tr ',' '\n' > r2_col
    paste s_col a_col r1_col r2_col > manifest.tsv

    # make directory structure
    mkdir -p \
        !{cluster_name}/ref \
        !{cluster_name}/snippy

    # select a reference genome
    ref=$(cat manifest.tsv | head -n 1 | cut -f 2)
    cp ${ref} !{cluster_name}/ref/ref.fa

    # run Snippy on each sample individually
    mkdir snippy_new
    echo '#!/bin/bash' > snippy_script.sh
    cat manifest.tsv | awk '{print "snippy --cleanup --cpus 8 --reference !{cluster_name}/ref/ref.fa --R1 "$3" --R2 "$4" --outdir snippy_new/"$1 }' >> snippy_script.sh
    bash snippy_script.sh
   
    # run snippy-core
    mkdir core
    cd core
    snippy-core --ref ../!{cluster_name}/ref/ref.fa ../snippy_new/* || true
    cd ../

    # compress outputs
    dirs=$(ls -d snippy_new/*/)
    for d in ${dirs}
    do
        name=${d%/}
        tar -czvf ${name##*/}.tar.gz ${d}
    done
    '''
}


process CALL_VARIANTS_OLD {
    container 'staphb/snippy:4.6.0-SC2'

    input:
    tuple val(taxa_cluster), val(samples), val(taxa), path(assemblies), path(fastq_1), path(fastq_2), val(cluster), val(status), path(cluster_dir)

    output:
    tuple val(cluster_name), val(taxa_name), path(cluster_name), path('*.tar.gz'), path("core/core.*"), val(status), emit: snippy_results

    when:
    task.ext.when == null || task.ext.when

    shell:
    assembly_names = assemblies.name
    fwd_reads = fastq_1.name
    rev_reads = fastq_2.name
    taxa_name = taxa[0]
    cluster_name = cluster[0]
    snippy_new = "snippy_new"
    '''
    # create .tsv of samples and their associated files
    echo !{samples} | tr -d '[] ' | tr ',' '\n' > s_col
    echo !{assembly_names} | tr -d '[] ' | tr ',' '\n' > a_col
    echo !{fwd_reads} | tr -d '[] ' | tr ',' '\n' > r1_col
    echo !{fwd_reads} | tr -d '[] ' | tr ',' '\n' > r2_col
    paste s_col a_col r1_col r2_col > manifest.tsv

    # run Snippy on each sample individually
    mkdir snippy_new
    echo '#!/bin/bash' > snippy_script.sh
    cat manifest.tsv | awk '{print "snippy --cleanup --cpus 8 --reference !{cluster_dir}/ref/ref.fa --R1 "$3" --R2 "$4" --outdir snippy_new/"$1 }' >> snippy_script.sh
    bash snippy_script.sh

    # run snippy-core
    ## check for previous samples
    mkdir core

    n=$(ls !{cluster_dir}/snippy/ | wc -l)
    if [[ $n > 0 ]]
    then
        mkdir snippy_old
        tars=$(ls !{cluster_dir}/snippy/*.tar.gz)
        for t in ${tars}
        do
            tar -xzvf ${t} -C snippy_old/
        done

       cd core
       snippy-core --ref ../!{cluster_dir}/ref/ref.fa ../snippy_old/* ../snippy_new/* || true
    else
       cd core
       snippy-core --ref ../!{cluster_dir}/ref/ref.fa ../snippy_new/* || true
    fi
    cd ../

    # compress outputs
    dirs=$(ls -d snippy_new/*/)
    for d in ${dirs}
    do
        name=${d%/}
        tar -czvf ${name##*/}.tar.gz ${d}
    done
    '''
}