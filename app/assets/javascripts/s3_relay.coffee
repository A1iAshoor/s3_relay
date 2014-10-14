displayFailedUpload = (progressColumn=null) ->
  if progressColumn
    progressColumn.text("File could not be uploaded")
  else
    alert("File could not be uploaded")

saveUrl = (uuid, filename, content_type, public_url) ->
  private_url = null

  $.ajax
    type: "POST"
    url: "/s3_relay/uploads"
    async: false
    data:
      uuid: uuid
      filename: filename
      content_type: content_type
      public_url: public_url
    success: (data, status, xhr) ->
      private_url = data.private_url
    error: (xhr) ->
      console.log xhr.responseText

  return private_url

uploadFiles = (container) ->
  fileInput = $("input.s3r-field", container)
  files = fileInput.get(0).files
  uploadFile(container, file) for file in files
  fileInput.val("")

uploadFile = (container, file) ->
  fileName = file.name

  $.ajax
    type: "GET"
    url: "/s3_relay/uploads/new"
    success: (data, status, xhr) ->
      formData = new FormData()
      xhr = new XMLHttpRequest()
      endpoint = data.endpoint

      formData.append("AWSAccessKeyID", data.awsaccesskeyid)
      formData.append("x-amz-server-side-encryption", data.x_amz_server_side_encryption)
      formData.append("key", data.key)
      formData.append("success_action_status", data.success_action_status)
      formData.append("acl", data.acl)
      formData.append("policy", data.policy)
      formData.append("signature", data.signature)
      formData.append("content-type", file.type)
      formData.append("file", file)

      uuid = data.uuid

      uploadList = $(".s3r-upload-list", container)
      uploadList.append("<tr id='#{uuid}'><td><div class='s3r-file-url'>#{fileName}</div></td><td class='s3r-progress'><div class='s3r-bar'><div class='s3r-meter'></div></div></td></tr>")
      fileColumn = $(".s3r-upload-list ##{uuid} .s3r-file-url", container)
      progressColumn = $(".s3r-upload-list ##{uuid} .s3r-progress", container)
      progressBar = $(".s3r-bar", progressColumn)
      progressMeter = $(".s3r-meter", progressColumn)

      xhr.upload.addEventListener "progress", (ev) ->
        percentage = ((ev.position / ev.totalSize) * 100.0).toFixed(0)
        progressMeter.css "width", "#{percentage}%"

      xhr.onreadystatechange = (ev) ->
        if xhr.readyState is 4
          progressBar.remove()

          if xhr.status == 201
            contentType = file.type
            publicUrl = $("Location", xhr.responseXML).text()
            privateUrl = saveUrl(uuid, fileName, contentType, publicUrl)

            if privateUrl == null
              displayFailedUpload(progressColumn)
            else
              fileColumn.html("<a href='#{privateUrl}'>#{fileName}</a>")

              virtualAttr = "#{container.data('parent')}[new_#{container.data('attribute')}_uuids]"
              hiddenField = "<input type='hidden' name='#{virtualAttr}[]' value='#{uuid}' />"
              container.append(hiddenField)

          else
            displayFailedUpload(progressColumn)
            console.log $("Message", xhr.responseXML).text()

      xhr.open "POST", endpoint, true
      xhr.send formData
    error: (xhr) ->
      displayFailedUpload()
      console.log xhr.responseText

jQuery ->

  $(document).on "change", ".s3r-field", ->
    uploadFiles($(this).parent())
