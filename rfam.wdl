workflow rfam {

  String imgap_input_fasta
  String imgap_project_id
  String imgap_project_type
  Int    additional_threads
  File   cmsearch_bin
  File   cm
  File   claninfo_tsv
  File   feature_lookup_tsv
  File   clan_filter_bin


  call cmsearch {
        input:
          bin = cmsearch_bin,
          input_fasta = imgap_input_fasta,
          project_id = imgap_project_id,
          cm = cm,
          threads = additional_threads
      }

  call clan_filter {
        input:
          clan_filter_bin = clan_filter_bin,
          project_id = imgap_project_id,
          tbl = cmsearch.tbl,
          cmsearch_bin = cmsearch_bin,
          claninfo_tsv = claninfo_tsv,
          feature_lookup_tsv = feature_lookup_tsv,
      }

  call misc_and_regulatory {
    input:
      rfam_gff = clan_filter.rfam_gff,
      project_id = imgap_project_id
  }

  call rrna {
    input:
      rfam_gff = clan_filter.rfam_gff,
      project_id = imgap_project_id
  }

  call ncrna_tmrna {
    input:
      rfam_gff = clan_filter.rfam_gff,
      project_id = imgap_project_id
  }

  output {
    File misc_bind_misc_feature_regulatory_gff = misc_and_regulatory.misc_bind_misc_feature_regulatory_gff
    File rrna_gff = rrna.rrna_gff
    File ncrna_tmrna_gff = ncrna_tmrna.ncrna_tmrna_gff
  }
}

task cmsearch {

  File   bin
  File   input_fasta
  String project_id
  File   cm
  Int    threads

  command {
    ${bin} --notextw --cut_tc --cpu ${threads} --tblout ${project_id}_rfam.tbl ${cm} ${input_fasta}
  }
  output {
    File tbl = "${project_id}_rfam.tbl"
  }
}

task clan_filter {

  File   clan_filter_bin
  String project_id
  File   tbl
  File   cmsearch_bin
  File   claninfo_tsv
  File   feature_lookup_tsv

  command <<<
    tool_and_version=$(${cmsearch_bin} -h | grep INFERNAL | cut -d' ' -f3)
    grep -v '^#' ${tbl} | \
    awk '$17 == "!" {print $1,$3,$4,$6,$7,$8,$9,$10,$11,$15,$16}' | \
    sort -k1,1 -k10,10nr -k11,11n | \
    ${clan_filter_bin} "$tool_and_version" \
    ${claninfo_tsv} ${feature_lookup_tsv} > ${project_id}_rfam.gff
  >>>
  output {
    File rfam_gff = "${project_id}_rfam.gff"
  }
}

task misc_and_regulatory {
  
  File   rfam_gff
  String project_id

  command <<<
    awk -F'\t' '$3 == "misc_bind" || $3 == "misc_feature" || $3 == "regulatory" {print $0}' \
    ${rfam_gff} > ${project_id}_rfam_misc_bind_misc_feature_regulatory.gff
  >>>
  output {
    File misc_bind_misc_feature_regulatory_gff = "${project_id}_rfam_misc_bind_misc_feature_regulatory.gff"
  }
}

task rrna {

  File   rfam_gff
  String project_id

  command <<<
    awk -F'\t' '$3 == "rRNA" {print $0}' ${rfam_gff} > ${project_id}_rfam_rrna.gff
  >>>
  output {
    File rrna_gff = "${project_id}_rfam_rrna.gff"
  }
}

task ncrna_tmrna {

  File   rfam_gff
  String project_id

  command <<<
    awk -F'\t' '$3 == "ncRNA" || $3 == "tmRNA" {print $0}' \
        ${rfam_gff} > ${project_id}_rfam_ncrna_tmrna.gff
  >>>
  output {
    File ncrna_tmrna_gff = "${project_id}_rfam_ncrna_tmrna.gff"
  }
}
