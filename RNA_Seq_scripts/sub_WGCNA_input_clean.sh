#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -pe smp 4
#$ -l h_vmem=8G
#$ -l h=blacklace01.blacklace|blacklace02.blacklace|blacklace04.blacklace|blacklace05.blacklace|blacklace06.blacklace|blacklace07.blacklace|blacklace08.blacklace|blacklace09.blacklace|blacklace10.blacklace|blacklace11.blacklace

scripts=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts

/home/adamst/prog/R/R-3.2.5/bin/Rscript --vanilla $scripts/WGCNA_input_clean.R --gene_table $1 --out_dir $2 --FPKM_start $3 --FPKM_end $4
