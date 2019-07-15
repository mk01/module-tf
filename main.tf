variable hosts { type = "list" }
variable iids { type = "list" }
variable files { type = "list" default = [] }
variable commands { type = "list" default = [] }
variable destination-directory { default = "" }
variable host-count { }
variable sudo-required { default = false }

locals {
  check-command = "${length(join("", data.null_data_source.check-sudo-needed-iter.*.outputs.value)) > 0 || var.sudo-required ? "sudo true" : "true"}"
  destination-directory = "${length(var.destination-directory) > 0 ? var.destination-directory : "."}"
}

resource null_resource check-hosts-up {
  triggers { instanceid = "${var.iids[count.index]}" }

  provisioner local-exec {
    command = "while ! host ${var.hosts[count.index]}; do sleep 5; done > /dev/null 2>&1"
  }

  count = "${var.host-count}"
}

data null_data_source check-sudo-needed-iter {
  inputs {
    value = "${var.commands[count.index] == replace(var.commands[count.index], "sudo", "") ? "" : "yes"}"
  }
  count = "${length(var.commands)}"
}

resource null_resource check-ssh-works {
  depends_on = ["null_resource.check-hosts-up"]
  triggers { instanceid = "${var.iids[count.index]}" }

  provisioner local-exec {
    command = "while ! ssh ${data.dns_ptr_record_set.dns_names.*.ptr[count.index]} '${local.check-command}'; do sleep 5; done > /dev/null 2>&1"
  }

  count = "${var.host-count}"
}

data dns_ptr_record_set dns_names {
  depends_on = ["null_resource.check-hosts-up"]

  ip_address = "${var.hosts[count.index]}"

  count = "${var.host-count}"
}

resource null_resource upload {
  depends_on = ["null_resource.check-ssh-works"]
  triggers { instanceid = "${var.iids[count.index / length(var.files)]}" }

  provisioner local-exec {
    command = "ssh ${data.dns_ptr_record_set.dns_names.*.ptr[count.index / length(var.files)]} 'export CMD=${local.destination-directory}; mkdir -p $CMD'"
  }

  provisioner local-exec {
    command = "scp ${var.files[count.index % length(var.files)]} ${data.dns_ptr_record_set.dns_names.*.ptr[count.index / length(var.files)]}:${local.destination-directory}"
  }

  provisioner local-exec {
    command = "ssh ${data.dns_ptr_record_set.dns_names.*.ptr[count.index / length(var.files)]} 'export CMD=${local.destination-directory}/$(basename ${var.files[count.index % length(var.files)]}); test -x $CMD && $CMD ||:'"
  }

  count = "${var.host-count * length(var.files)}"
}

resource null_resource exec {
  depends_on = ["null_resource.upload"]
  triggers { instanceid = "${var.iids[count.index / length(var.commands)]}" }

  provisioner local-exec {
    command = "ssh ${data.dns_ptr_record_set.dns_names.*.ptr[count.index / length(var.commands)]} 'export INR=${count.index / length(var.commands)}; ${var.commands[count.index % length(var.commands)]}'"
  }

  count = "${var.host-count * length(var.commands)}"
}

output dns-names {
  value = "${data.dns_ptr_record_set.dns_names.*.ptr}"
}
