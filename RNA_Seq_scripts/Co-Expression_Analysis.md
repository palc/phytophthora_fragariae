Initial analysis of RNA-Seq data was performed in RNA-Seq_analysis.md
this performs co-expression analyses and searches for potential promotor motifs.

# Four key stages of analysis to be performed

A) Building a coexpression network and export it
B) Counting kmers in the 3kb upstream region of all genes in the coexpressed set
C) Test these kmers for enrichment

## A) Building a coexpression network

The threshold for samples depends on the dataset,
make sure to sanity check with the output graph
cluster to keep may also need to be modified

All columns MUST have headers

```bash
OutDir=analysis/coexpression
mkdir -p $OutDir
ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
gene_table=gene_pred/annotation/P.fragariae/Bc16/Bc16_gene_table_incl_exp.tsv
FPKM_start=27
FPKM_end=34
qsub $ProgDir/sub_WGCNA_input_clean.sh $gene_table $OutDir $FPKM_start $FPKM_end
```

```
22,370 genes were removed due to too many missing samples or zero variance.
Listed in analysis/coexpression/removed_genes.txt
The candidate Avr is not in this list, so it is not too strict about genes
with low expression in some samples
```

Test various values of soft thresholding for building the network

```bash
OutDir=analysis/coexpression
ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
max_SFT=40
qsub $ProgDir/sub_choose_softthreshold.sh $OutDir $max_SFT
```

```
scale-free topology fit index values seem to peak and then decline.
WGCNA tutorial recommends getting as close to 0.9 as possible,
but 22 has a value of 0.8750 and is the highest reached before declining.
```

Build the coexpression network
Merging threshold value may need tweaking

```bash
OutDir=analysis/coexpression
ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
SFT=22
Min_Mod_Size=30
Merge_Threshold=0.25
qsub $ProgDir/sub_create_network.sh $OutDir $SFT $Min_Mod_Size $Merge_Threshold
```

Export gene lists

Y or N denotes whether unmerged modules will be exported too

```bash
OutDir=analysis/coexpression
ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
qsub $ProgDir/sub_Export_Gene_Lists.sh $OutDir Y
```

```
Number of merged modules: 31
Number of unmerged modules: 112
```

```
In merged modules:
Candidate Avr (g27513) is in red with 1,021 genes

In unmerged modules:
Candidate Avr (27513) is in saddlebrown with 197 genes
```

Export network for external visualisation with Cytoscape
<http://www.cytoscape.org/?gclid=CjwKCAjws6jVBRBZEiwAkIfZ2lpzRXx8WFD-1wk-tD4KOHW6ZIafetKcptpSIfnyc82PDbFt83h9HBoCtjEQAvD_BwE>

```bash
OutDir=analysis/coexpression
ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
Module=red
qsub $ProgDir/sub_export_network_cytoscape.sh $OutDir $Module
```

Genes from the module were visually inspected for promotor hunting
This gave 29 high confidence genes and 31 lower confidence genes
Also analyse all genes with an fpkm value above 9,000
in at least one BC-16 timepoint, 6 genes
Also run the entirety of saddlebrown, 197 genes so might work better

Extract the 3000 bases upstream of these genes

```bash
for Headers in $(ls promotor_id/*genes.txt)
do
    Sequences=gene_pred/annotation/P.fragariae/Bc16/Bc16_genes_incl_ORFeffectors.upstream3000.fasta
    ProgDir=/home/adamst/git_repos/tools/gene_prediction/ORF_finder
    OutDir=promotor_id
    File_ID=$(echo $Headers | cut -f2 -d '/' | cut -f1 -d '_')
    sed -i 's/\.t1/_upstream3000/g' $Headers
    $ProgDir/extract_from_fasta.py --fasta $Sequences --headers $Headers > $OutDir/"$File_ID"_upstream3000.fasta
done
```

Convert all bases to uppercase

```bash
for input in $(ls promotor_id/*.fasta)
do
    filename=$(echo $input | cut -f1 -d '.')
    input_modified="$filename"_modified.fasta
    cat $input | awk 'BEGIN{FS=" "}{if(!/>/){print toupper($0)}else{print $1}}' \
    > $input_modified
    rm $input
    mv $input_modified $input
done
```

Remove duplicate genes

```bash
for input in $(ls promotor_id/*.fasta)
do
    filename=$(echo $input | cut -f1 -d '.')
    input_modified="$filename"_modified.fasta
    awk 'BEGIN{RS=">"}NR>1{sub("\n","\t"); gsub("\n",""); print RS$0}' $input | awk '!seen[$1]++' | awk -v OFS="\n" '{print $1,$2}' > $input_modified
    rm $input
    mv $input_modified $input
done
```

## B) Identifying novel motifs using DREME

### Set up files

Organise directories and create files for a comparison set to sample from

```bash
cat gene_pred/annotation/P.fragariae/Bc16/Bc16_genes_incl_ORFeffectors_renamed.upstream3000.fasta | grep '>' | sed 's/>//g' > promotor_id/Total_Gene_Set.txt
for Set in allconf highconf highexp saddlebrown
do
    mkdir -p promotor_id/$Set
    mv promotor_id/"$Set"_genes.txt promotor_id/$Set/.
    mv promotor_id/"$Set"_upstream3000.fasta promotor_id/$Set/.
    cat promotor_id/Total_Gene_Set.txt | grep -vf promotor_id/$Set/"$Set"_genes.txt > promotor_id/$Set/"$Set"_nontarget.txt
    ProgDir=/home/adamst/git_repos/tools/gene_prediction/ORF_finder
    Fasta=gene_pred/annotation/P.fragariae/Bc16/Bc16_genes_incl_ORFeffectors.upstream3000.fasta
    Headers=promotor_id/$Set/"$Set"_nontarget.txt
    Output=promotor_id/$Set/"$Set"_nontarget_upstream3000.fasta
    echo "Extracting fasta for $Set"
    $ProgDir/extract_from_fasta.py --fasta $Fasta --headers $Headers > $Output
    echo "$Set done"
done
```

Split fasta file into 100bp sequences

Before running, install pyfasta

```bash
pip install https://pypi.python.org/packages/be/3f/794fbcdaaa2113f0a1d16a962463896c1a6bdab77bd63f33a8f16aae6cdc/pyfasta-0.5.2.tar.gz --user
```

To use this module, add the following line to your profile

```bash
export PYTHONPATH="$PYTHONPATH:/home/adamst/.local/lib/python2.7/site-packages"
export PATH=${PATH}:/home/adamst/.local/bin
```

Now split target files into 100bp sequences

```bash
for Set in allconf highconf highexp saddlebrown
do
    WorkDir=promotor_id/$Set
    Fasta=$WorkDir/"$Set"_upstream3000.fasta
    pyfasta split -n 1 -k 100 $Fasta
done
```

Convert all bases to uppercase in non-target files

```bash
for Set in allconf highconf highexp saddlebrown
do
    for input in $(ls promotor_id/$Set/"$Set"_nontarget_upstream3000.fasta)
    do
        filename=$(echo $input | cut -f1 -d '.')
        input_modified="$filename"_modified.fasta
        cat $input | awk 'BEGIN{FS=" "}{if(!/>/){print toupper($0)}else{print $1}}' \
        > $input_modified
        rm $input
        mv $input_modified $input
    done
done
```

Remove duplicate genes in non-target files

```bash
for Set in allconf highconf highexp saddlebrown
do
    for input in $(ls promotor_id/$Set/"$Set"_nontarget_upstream3000.fasta)
    do
        filename=$(echo $input | cut -f1 -d '.')
        input_modified="$filename"_modified.fasta
        awk 'BEGIN{RS=">"}NR>1{sub("\n","\t"); gsub("\n",""); print RS$0}' $input | awk '!seen[$1]++' | awk -v OFS="\n" '{print $1,$2}' > $input_modified
        rm $input
        mv $input_modified $input
    done
done
```

Now split non-target files into 100bp sequences

```bash
for Set in allconf highconf highexp saddlebrown
do
    WorkDir=promotor_id/$Set
    Fasta=$WorkDir/"$Set"_nontarget_upstream3000.fasta
    pyfasta split -n 1 -k 100 $Fasta
done
```

### Create negative samples for each set

```bash
for Set in allconf highconf highexp saddlebrown
do
    for Rep in {1..100}
    do
        WorkDir=promotor_id/$Set
        Pos_Fasta=$WorkDir/"$Set"_upstream3000.split.100mer.fasta
        Neg_Fasta=$WorkDir/"$Set"_nontarget_upstream3000.split.100mer.fasta
        Num_of_Seqs=$(cat $Pos_Fasta | grep '>' | wc -l)
        ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
        OutDir=/data/scratch/adamst/$Set
        mkdir -p $OutDir
        Jobs=$(qstat | grep 'sub_fasta' | wc -l)
        while [ $Jobs -gt 20 ]
        do
            sleep 1
            printf "."
            Jobs=$(qstat | grep 'sub_fasta' | wc -l)
        done
        qsub $ProgDir/sub_fasta_subsample.sh $Neg_Fasta $Num_of_Seqs $Rep $OutDir
    done
done
```

### DREME motif analysis

fifth command line argument is e-value, default and recommended is 0.05
Increasing will provide more motifs, but they may not be significantly enriched

```bash
for Set in allconf highconf highexp saddlebrown
do
    for Rep in {1..100}
    do
        WorkDir=promotor_id/$Set
        NegDir=/data/scratch/adamst/$Set
        Positive=$WorkDir/"$Set"_upstream3000.split.100mer.fasta
        Negative=$NegDir/"$Set"_nontarget_upstream3000.split.100mer_random_*_"$Rep".fasta
        ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
        Jobs=$(qstat | grep 'sub_dreme' | wc -l)
        while [ $Jobs -gt 20 ]
        do
            sleep 1
            printf "."
            Jobs=$(qstat | grep 'sub_dreme' | wc -l)
        done
        qsub $ProgDir/sub_dreme.sh $Positive $Negative $NegDir $Rep 0.25
    done
done
```

Combine results from multiple repeats

```bash
for Set in allconf highconf highexp saddlebrown
do
    OutDir=promotor_id/$Set
    DremeDir=/data/scratch/adamst/$Set
    DremeRes=$DremeDir/*dreme*/dreme.txt
    Percentage=90
    ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
    python $ProgDir/Combine_DREME_Repeats.py --inputs $DremeRes \
    --percentage $Percentage --outdir $OutDir
done
```

Nothing can be reproducibly pulled out, possibly due to the small input sample size
Or due to the lack of a true negative control set

## Investigate enrichment of effector class genes in co-expression modules

### Create lists of RxLRs, CRNs, ApoplastP hits, a combined list of all effectors and a list of secreted proteins

Remove statement from beginning of removed_genes file from WGCNA
Create files for Genomic sets of Genes and features

```bash
cat analysis/coexpression/removed_genes.txt | sed 's/Removing genes: //g' > analysis/coexpression/removed_genes.txt
Removed_Genes=analysis/coexpression/removed_genes.txt

# All genes

Gene_Set=analysis/coexpression/Genes_for_WGCNA.txt
Genome_Fasta=gene_pred/annotation/P.fragariae/Bc16/Bc16_genes_incl_ORFeffectors_renamed.cdna.fasta
Genome_Headers=gene_pred/annotation/P.fragariae/Bc16/Bc16_genes_incl_ORFeffectors_renamed_Headers.txt
cat $Genome_Fasta | grep '>' | sort | uniq > $Genome_Headers
cat $Genome_Headers | grep -wvf $Removed_Genes | sort | uniq > $Gene_Set

# RxLRs

RxLR_Set=analysis/coexpression/RxLRs_analysed.txt
RxLR_Headers=analysis/RxLR_effectors/combined_evidence/P.fragariae/Bc16/Bc16_Total_RxLR_motif_hmm_renamed.txt
cat $RxLR_Headers | grep -wf $Gene_Set | sort | uniq > $RxLR_Set

# CRNs

CRN_Set=analysis/coexpression/CRNs_analysed.txt
CRN_Headers=analysis/CRN_effectors/hmmer_CRN/P.fragariae/Bc16/Bc16_final_CRN_renamed.txt
cat $CRN_Headers | grep -wf $Gene_Set | sort | uniq > $CRN_Set

# ApoP

ApoP_Set=analysis/coexpression/ApoP_analysed.txt
ApoP_Headers=analysis/ApoplastP/P.fragariae/Bc16/Bc16_Total_ApoplastP_renamed.txt
cat $ApoP_Headers | grep -wf $Gene_Set | sort | uniq > $ApoP_Set

# Effectors

Effector_Set=analysis/coexpression/Effectors_analysed.txt
cat $RxLR_Set $CRN_Set $ApoP_Set | sort | uniq > $Effector_Set

# Secreted proteins

Secreted_Set=analysis/coexpression/Secreted_analysed.txt
Secreted_preds=gene_pred/combined_sigP_CQ/P.fragariae/Bc16/Bc16_all_secreted_Aug_ORF.txt
cat $Secreted_preds | grep -wf $Gene_Set | sort | uniq > $Secreted_Set
```

Create files for Module sets of Genes and features

```bash
for File in $(ls analysis/coexpression/merged_modules/Genes_in_*.txt)
do
    Filename=$(echo $File | rev | cut -f1 -d "/" | rev)
    Module_ID=$(echo $Filename | cut -f3 -d "_" | cut -f1 -d ".")
    echo "Processing $Module_ID"
    Module_Dir=analysis/coexpression/enrichment/$Module_ID
    mkdir -p $Module_Dir
    Gene_Set_unsorted=$Module_Dir/Gene_Set_unsorted.txt
    Gene_Set=$Module_Dir/Gene_Set.txt
    # Copy entire gene set of module
    cp $File $Gene_Set_unsorted
    cat $Gene_Set_unsorted | sed 's/"//g' | sort | uniq > $Gene_Set
    rm $Gene_Set_unsorted
    echo "Gene set file created for $Module_ID"
    # Create RxLR list
    RxLR_Headers=analysis/RxLR_effectors/combined_evidence/P.fragariae/Bc16/Bc16_Total_RxLR_motif_hmm_renamed.txt
    RxLRs_In_Module=$Module_Dir/RxLR_IDs.txt
    cat $RxLR_Headers | grep -wf $Gene_Set | sort | uniq > $RxLRs_In_Module
    echo "RxLR file created for $Module_ID"
    # Create CRN list
    CRN_Headers=analysis/CRN_effectors/hmmer_CRN/P.fragariae/Bc16/Bc16_final_CRN_renamed.txt
    CRNs_In_Module=$Module_Dir/CRN_IDs.txt
    cat $CRN_Headers | grep -wf $Gene_Set | sort | uniq > $CRNs_In_Module
    echo "CRN file created for $Module_ID"
    # Create list of ApoplastP hits
    ApoP_Headers=analysis/ApoplastP/P.fragariae/Bc16/Bc16_Total_ApoplastP_renamed.txt
    ApoP_In_Module=$Module_Dir/ApoP_IDs.txt
    cat $ApoP_Headers | grep -wf $Gene_Set | sort | uniq > $ApoP_In_Module
    echo "ApoplastP hits file created for $Module_ID"
    # Create combined effector list
    Effectors_In_Module=$Module_Dir/Effector_IDs.txt
    cat $RxLRs_In_Module $CRNs_In_Module $ApoP_In_Module | sort | uniq > $Effectors_In_Module
    echo "Effector list created for $Module_ID"
    # Create combined secreted proteins list
    Secreted_In_Module=$Module_Dir/Secreted_IDs.txt
    Secreted_preds=gene_pred/combined_sigP_CQ/P.fragariae/Bc16/Bc16_all_secreted_Aug_ORF.txt
    cat $Secreted_preds | grep -wf $Gene_Set | sort | uniq > $Secreted_In_Module
    echo "Secreted list created for $Module_ID"
done
```

### Create contigency tables for fishers exact test

```bash
RxLR_Headers=analysis/RxLR_effectors/combined_evidence/P.fragariae/Bc16/Bc16_Total_RxLR_motif_hmm_renamed.txt
Genome_RxLRs=$(cat $RxLR_Headers | sort | uniq | wc -l)
CRN_Headers=analysis/CRN_effectors/hmmer_CRN/P.fragariae/Bc16/Bc16_final_CRN_renamed.txt
Genome_CRNs=$(cat $CRN_Headers | sort | uniq | wc -l)
ApoP_Headers=analysis/ApoplastP/P.fragariae/Bc16/Bc16_Total_ApoplastP_renamed.txt
Genome_ApoP=$(cat $ApoP_Headers | sort | uniq | wc -l)
Genome_Effectors=$(cat $RxLR_Headers $CRN_Headers $ApoP_Headers | sort | uniq | wc -l)
Secreted_preds=gene_pred/combined_sigP_CQ/P.fragariae/Bc16/Bc16_all_secreted_Aug_ORF.txt
Genome_Secreted=$(cat $Secreted_preds | sort | uniq | wc -l)
Genes=gene_pred/annotation/P.fragariae/Bc16/Bc16_genes_incl_ORFeffectors_renamed.gene.fasta
Genome_Genes=$(cat $Genes | grep '>' | sort | uniq | wc -l)
for Module_Dir in $(ls -d analysis/coexpression/enrichment/*)
do
    Module_Name=$(echo $Module_Dir | rev | cut -f1 -d "/" | rev)
    Module_RxLRs=$Module_Dir/RxLR_IDs.txt
    Module_CRNs=$Module_Dir/CRN_IDs.txt
    Module_ApoP=$Module_Dir/ApoP_IDs.txt
    Module_Effectors=$Module_Dir/Effector_IDs.txt
    Module_Secreted=$Module_Dir/Secreted_IDs.txt
    Module_Genes=$Module_Dir/Gene_Set.txt
    ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
    echo "Processing $Module_Name"
    python $ProgDir/Fisher_table_prep.py --Module_RxLRs $Module_RxLRs --Module_CRNs $Module_CRNs --Module_ApoP $Module_ApoP --Module_Effectors $Module_Effectors --Module_Secreted $Module_Secreted --Module_Genes $Module_Genes --Module_Name $Module_Name --Genome_RxLRs $Genome_RxLRs --Genome_CRNs $Genome_CRNs --Genome_ApoP $Genome_ApoP --Genome_Effectors $Genome_Effectors --Genome_Secreted $Genome_Secreted --Genome_Genes $Genome_Genes --OutDir $Module_Dir
    echo "$Module_Name done"
done
```

### Run Fishers Exact test to test for enrichment

WARNING: if running in a screen session, rerun the following command after opening screen

```bash
. ~/.profile
```

```bash
for Table in $(ls analysis/coexpression/enrichment/*/*Fishertable.txt)
do
    Module_ID=$(echo $Table | rev | cut -f2 -d "/" | rev)
    Filename=$(echo $Table | rev | cut -f1 -d "/" | rev)
    Gene_Type=$(echo $Filename | cut -f2 -d "_")
    OutDir=analysis/coexpression/enrichment/$Module_ID/Fisher_Results
    mkdir -p $OutDir
    ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
    echo "Running $Module_ID" "$Gene_Type"
    /home/adamst/prog/R/R-3.2.5/bin/Rscript --vanilla $ProgDir/fisherstest.R --Input_Table $Table --Output_Directory $OutDir --Module_ID $Module_ID --Gene_Type $Gene_Type
    echo "$Module_ID" "$Gene_Type done"
done
```

Parse fisher results files to fewer files by type and hypothesis being tested

```bash
for Type in up down equal
do
    Files=$(ls analysis/coexpression/enrichment/*/Fisher_Results/enriched_"$Type".txt)
    OutDir=analysis/coexpression/enrichment/Parsed_Fisher_Results/$Type
    mkdir -p $OutDir
    ProgDir=/home/adamst/git_repos/scripts/phytophthora_fragariae/RNA_Seq_scripts
    python $ProgDir/parse_fisher_results.py --inputs $Files --outdir $OutDir --FDR 0.05 --Threshold 0.05
done
```

None are listed as equal, so this execution of the script fails
