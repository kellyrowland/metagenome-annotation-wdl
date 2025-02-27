#!/usr/bin/env bash

if [[ $# -lt 2 || $# -gt 8 ]]
then
	printf "Usage: $(basename $0) <proteins_fasta> <funfam_hmm_db> " >&2
	printf "<number_of_additional_threads (default: 0)> " >&2
	printf "<number_of_parallel_hmmsearch_instances (default: 0)> " >&2
	printf "<approximate_number_of_total_proteins (default: 0)> " >&2
	printf "<min_domain_evalue_cutoff (default 0.01)> " >&2
	printf "<min_aln_length_ratio (default 0.7)> " >&2
	printf "<max_overlap_ratio (default 0.1)>\n" >&2
	exit 1
fi


proteins_fasta=$1
if [[ ! -f $proteins_fasta ]]
then
	echo "$proteins_fasta is not a file! Aborting!" >&2
	exit 1
fi

funfam_hmm_db=$2
if [[ ! -f $funfam_hmm_db ]]
then
	echo "$funfam_hmm_db is not a file! Aborting!" >&2
	exit 1
fi

number_of_additional_threads=0
if [[ ! -z "$3" ]]
then
	number_of_additional_threads=$3
fi

number_of_parallel_hmmsearch_instances=0
if [[ ! -z "$4" ]]
then
	number_of_parallel_hmmsearch_instances=$4
fi

approximate_number_of_total_proteins=0
if [[ ! -z "$5" ]]
then
	approximate_number_of_total_proteins=$5
fi

min_domain_evalue_cutoff=0.01
if [[ ! -z "$6" ]]
then
	min_domain_evalue_cutoff=$6
fi

min_aln_length_ratio=0.7
if [[ ! -z "$7" ]]
then
	min_aln_length_ratio=$7
fi

max_overlap_ratio=0.0
if [[ ! -z "$8" ]]
then
	max_overlap_ratio=$8
fi


if [[ $number_of_additional_threads -gt $number_of_parallel_hmmsearch_instances ]]
then
    hmmsearch_threads=$(echo $number_of_additional_threads / $number_of_parallel_hmmsearch_instances | bc)
    printf "$(date +%F_%T) - Splitting up proteins fasta into $number_of_parallel_hmmsearch_instances "
    printf "pieces now and then run hmmsearch on them separately with $hmmsearch_threads "
    printf "threads each against the Cath-FunFam db...\n"
    tmp_dir=$(dirname $proteins_fasta)
    filesize=$(ls -l $proteins_fasta | awk '{print $5}')
    blocksize=$((($filesize / $number_of_parallel_hmmsearch_instances) + 20000))

    hmmsearch_base_cmd="hmmsearch --notextw --domE $min_domain_evalue_cutoff"
    if [[ $approximate_number_of_total_proteins -gt 0 ]]
    then
        hmmsearch_base_cmd="$hmmsearch_base_cmd -Z $approximate_number_of_total_proteins"
    fi
    hmmsearch_base_cmd="$hmmsearch_base_cmd --cpu $hmmsearch_threads "
    # Use parallel to split up the input and
    # run hmmsearch in parallel on those splits
    cat $proteins_fasta | parallel --pipe --recstart '>' \
                            --blocksize $blocksize \
                            'cat > '$tmp_dir'/tmp.$$.split.faa; ' \
                            $hmmsearch_base_cmd \
			                '--domtblout '$tmp_dir'/tmp.cath_funfam.$$.domtblout' \
    		                $funfam_hmm_db $tmp_dir'/tmp.$$.split.faa 1> /dev/null;'
    exit_code=$?
    if [[ $exit_code -ne 0 ]]
    then
        echo "GNU parallel run failed! Aborting!" >&2
        exit $exit_code
    fi

    echo "$(date +%F_%T) - Concatenating split result files now..."
    cat $tmp_dir/tmp.cath_funfam.* > ${proteins_fasta%.*}.cath_funfam.domtblout
    exit_code=$?
    if [[ $exit_code -ne 0 ]]
    then
        echo "Concatenating split outputs failed! Aborting!" >&2
        exit $exit_code
    fi

    echo "$(date +%F_%T) - Deleting tmp files now..."
    rm $tmp_dir/tmp.*
else
    echo "$(date +%F_%T) - Calling hmmsearch to predict Cath-FunFams now..."
    hmmsearch_cmd="hmmsearch --notextw --domE $min_domain_evalue_cutoff"
    if [[ $approximate_number_of_total_proteins -gt 0 ]]
    then
        hmmsearch_cmd="$hmmsearch_cmd -Z $approximate_number_of_total_proteins"
    fi
    hmmsearch_cmd="$hmmsearch_cmd --domtblout ${proteins_fasta%.*}.cath_funfam.domtblout "
    hmmsearch_cmd="$hmmsearch_cmd $funfam_hmm_db $proteins_fasta 1> /dev/null"
    $hmmsearch_cmd
    exit_code=$?
    if [[ $exit_code -ne 0 ]]
    then
        echo "$(date +%F_%T) - hmmsearch failed! Aborting!" >&2
        exit $exit_code
    fi
fi

echo "$(date +%F_%T) - Getting hmmsearch version now..."
tool_and_version=$(hmmsearch -h | grep HMMER)
tool_and_version=${tool_and_version%%;*}
tool_and_version=${tool_and_version:2}

echo "$(date +%F_%T) - Filtering fragmets and converting output to gff now..."
funfam_gff=${proteins_fasta%_*}_cath_funfam.gff
grep -v '^#' ${proteins_fasta%.*}.cath_funfam.domtblout | \
awk '{print $1,$3,$4,$5,$6,$7,$8,$13,$14,$16,$17,$20,$21}' | \
sort -k1,1 -k7,7nr -k6,6n | \
$(dirname $0)/hmmsearch_fragmented_hits_filter.py -a $min_aln_length_ratio \
												  -o $max_overlap_ratio \
											      "$tool_and_version" > $funfam_gff
exit_code=$?
if [[ $exit_code -ne 0 ]]
then
	echo "$(date +%F_%T) - One of the pipe commands failed! Aborting!" >&2
	exit $exit_code
fi

echo "$(date +%F_%T) - Done with Cath-FunFam annotation."
