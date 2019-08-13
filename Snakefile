ACCESSIONS = [
  "ACBarrie",
  "Alsen",
  "Baxter",
  "Chara",
  "Drysdale",
  "Excalibur",
  "Gladius",
  "H45",
  "Kukri",
  "Pastor",
  "RAC875",
  "Volcanii",
  "Westonia",
  "Wyalkatchem",
  "Xiaoyan",
  "Yitpi",
]

MAX_THREADS = 32
ADAPTERS = "TruSeq3-PE.fa"

from snakemake.remote.HTTP import RemoteProvider as HTTPRemoteProvider
HTTP = HTTPRemoteProvider()

singularity:
#	"docker://continuumio/miniconda3:4.6.14"
	"docker://rsuchecki/miniconda3:4.6.14_050661b0ef92865fde5aea442f3440d1a7532659"
#	"docker://rsuchecki/nextflow-embl-abr-webinar"

#######################################
# Convienient rules to define targets #
#######################################
localrules:
	all,
	setup_data,
	qc_reads

rule all:
	input:
		"reports/raw_reads_multiqc.html",
		expand("qc_reads/{accession}_R{read}.fastq.gz", accession=ACCESSIONS, read=[1,2]),
		"reports/qc_reads_multiqc.html",
		expand("mapped/{accession}.bam", accession=ACCESSIONS),


rule setup_data:
	input:
		"references/reference.fasta.gz",
		expand("raw_reads/{accession}_R{read}.fastq.gz", accession=ACCESSIONS, read=[1,2]),

rule qc_reads:
	input:
		expand("qc_reads/{accession}_R{read}.fastq.gz", accession=ACCESSIONS, read=[1,2]),


################
# Rules Proper #
################

rule fastqc_raw:
	input:
		"raw_reads/{prefix}.fastq.gz",
	output:
		zip  = "reports/raw_reads/{prefix}_fastqc.zip",
		html = "reports/raw_reads/{prefix}_fastqc.html",
	conda:
		"envs/tutorial.yml"
	threads:
		MAX_THREADS
	shell:
		"""
		fastqc --threads {threads} {input}
		mv raw_reads/{wildcards.prefix}_fastqc.zip {output.zip}
		mv raw_reads/{wildcards.prefix}_fastqc.html {output.html}
		"""

rule multiqc_raw:
	input:
		expand("reports/raw_reads/{accession}_R{read}_fastqc.zip", accession=ACCESSIONS, read=[1,2]),
	output:
		html  = "reports/raw_reads_multiqc.html",
		log   = "reports/raw_reads_multiqc_data/multiqc.log",
		json  = "reports/raw_reads_multiqc_data/multiqc_data.json",
		txt   = "reports/raw_reads_multiqc_data/multiqc_fastqc.txt",
		stats = "reports/raw_reads_multiqc_data/multiqc_general_stats.txt",
		src   = "reports/raw_reads_multiqc_data/multiqc_sources.txt",

	conda:
		"envs/tutorial.yml"
	shell:
		"""
		multiqc --force --filename {output.html} {input}
		"""

rule download_trimmomatic_pe_adapters:
	input:
		HTTP.remote("raw.githubusercontent.com/timflutre/trimmomatic/master/adapters/{adapters}", keep_local=True),
	output:
		"misc/trimmomatic_adapters/{adapters}"
	conda:
		"envs/tutorial.yml"
	shell:
		"""
		mv {input} {output}
		"""

rule trimmomatic_pe:
	input:
		r1          = "raw_reads/{prefix}_R1.fastq.gz",
		r2          = "raw_reads/{prefix}_R2.fastq.gz",
		adapters    = "misc/trimmomatic_adapters/" + ADAPTERS
	output:
		r1          = "qc_reads/{prefix}_R1.fastq.gz",
		r2          = "qc_reads/{prefix}_R2.fastq.gz",
		# reads where trimming entirely removed the mate
		r1_unpaired = "qc_reads/{prefix}_R1.unpaired.fastq.gz",
		r2_unpaired = "qc_reads/{prefix}_R2.unpaired.fastq.gz",
	conda:
		"envs/tutorial.yml"
	params:
		trimmer = [
			"ILLUMINACLIP:misc/trimmomatic_adapters/" + ADAPTERS + ":2:30:10:3:true",
			"LEADING:2",
			"TRAILING:2",
			"SLIDINGWINDOW:4:15",
			"MINLEN:36",
		],
	shell:
		"""
		trimmomatic PE \
		  -threads {threads} \
		  {input.r1} {input.r2} \
		  {output.r1} {output.r1_unpaired} \
		  {output.r2} {output.r2_unpaired} \
		  {params.trimmer}
		"""

rule fastqc_trimmed:
	input:
		"qc_reads/{prefix}.fastq.gz",
	output:
		zip  = "reports/qc_reads/{prefix}_fastqc.zip",
		html = "reports/qc_reads/{prefix}_fastqc.html",
	conda:
		"envs/tutorial.yml"
	shell:
		"""
		fastqc --threads {threads} {input}
		mv qc_reads/{wildcards.prefix}_fastqc.zip {output.zip}
                mv qc_reads/{wildcards.prefix}_fastqc.html {output.html}
		"""

rule multiqc_trimmed:
	input:
		expand("reports/qc_reads/{accession}_R{read}_fastqc.zip", accession=ACCESSIONS, read=[1,2]),
	output:
		html  = "reports/qc_reads_multiqc.html",
		log   = "reports/qc_reads_multiqc_data/multiqc.log",
		json  = "reports/qc_reads_multiqc_data/multiqc_data.json",
		txt   = "reports/qc_reads_multiqc_data/multiqc_fastqc.txt",
		stats = "reports/qc_reads_multiqc_data/multiqc_general_stats.txt",
		src   = "reports/qc_reads_multiqc_data/multiqc_sources.txt",
	conda:
		"envs/tutorial.yml"
	shell:
		"""
		multiqc --force --filename {output.html} {input}
		"""

rule bwa_index:
	input:
		"{ref}"
	output:
		"{ref}.amb",
		"{ref}.ann",
		"{ref}.bwt",
		"{ref}.pac",
		"{ref}.sa"
	conda:
		"envs/tutorial.yml"
#	log:
#		"logs/bwa_index/{ref}.log"
	params:
		prefix    = "{ref}",
		algorithm = "bwtsw"
	shell:
		"""
		bwa index \
		  -p {params.prefix} \
		  -a {params.algorithm} \
		  {input}
		"""

rule bwa_mem:
	input:
		reference = expand("references/reference.fasta.gz.{ext}", ext=["amb","ann","bwt","pac","sa"]),
		reads     = [ "qc_reads/{sample}_R1.fastq.gz", "qc_reads/{sample}_R2.fastq.gz"],
#		r1        = "qc_reads/{sample}_R1.fastq.gz",
#		r2        = "qc_reads/{sample}_R2.fastq.gz",
	output:
		"mapped/{sample}.bam"
	conda:
		"envs/tutorial.yml"
	params:
		index      = "references/reference.fasta.gz",
		extra      = r"-R '@RG\tID:{sample}\tSM:{sample}'",
		sort       = "none",
		sort_order = "queryname",
		sort_extra = ""
	threads:
		MAX_THREADS
	shell:
		"""
		bwa mem \
		  -t {threads} \
		  {params.extra} \
		  {params.index} \
		  {input.reads} \
		| samtools view -b > {output}
		"""

