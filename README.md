# s3_relay

[![Gem Version](https://badge.fury.io/rb/s3_relay.svg)](http://badge.fury.io/rb/s3_relay)
[![Code Climate](https://codeclimate.com/github/kjohnston/s3_relay/badges/gpa.svg)](https://codeclimate.com/github/kjohnston/s3_relay)

Enables direct file uploads to Amazon S3 and provides a flexible pattern for
your Rails app to asynchronously ingest the files.

## Overview

This Rails engine allows you to quickly implement direct uploads to Amazon S3
from your Ruby on Rails application.  It does not depend on any specific file
upload libraries, UI frameworks or AWS gems, like other solutions tend to.

It works by utilizing Amazon S3's
[Cross-Origin Resource Sharing](http://docs.aws.amazon.com/AmazonS3/latest/dev/cors.html)
to permit browser-based uploads directly to S3 with presigned URLs generated by
this gem with your application's API credentials.  As each file is uploaded,
the gem persists detail about the uploaded file in your application's database.
This table should be thought of much like a queue - think
[DelayedJob](https://github.com/collectiveidea/delayed_job) for your
uploaded-but-not-yet-ingested file uploads.

How (and if) you choose to import each uploaded file into your processing
library of choice is completely up to you.  The gem tracks the state of each
upload so that you may used the provided `.pending` scope and `mark_imported!`
method to fetch, process (via your background processor of choice), then
mark-off each upload record whose file has been successfully ingested by your
app.

## Features

* Files can be uploaded before or after your parent object has been saved.
* File upload fields can be placed inside or outside of your parent object's
form.
* File uploads display completion progress.
* Boilerplate styling can be used or easily replaced.
* All uploads are marked for [Server-Side Encryption by AWS](http://docs.aws.amazon.com/AmazonS3/latest/dev/UsingEncryption.html) so that they are encrypted upon
write to disk.  S3 then decrypts and streams the files as they are downloaded.
* Models can have multiple types of uploads and specify for each if only one
file is permitted or if multiple are.
* Multiple files can upload concurrently to S3.

## Technology & Requirements

Uploads are made possible by use of the `FormData` object, defined in
[XMLHttpRequest Level 2](http://dev.w3.org/2006/webapi/XMLHttpRequest-2/).
Many people are broadly referring to this as being provided by HTML5, but
technically it's part of the aforementioned spec that browsers have been
adhering to for a couple of major versions now.  Even IE, wuh?

The latest versions of all of the following are ideal, but here are the gem's
minimum requirements:

* For rails 5.1+, use version 0.6.x+ and ruby 2.3+
* For rails 3.1 to 5.0, use version 0.5.x and ruby 1.9.3+
* Modern versions of Chrome, Safari, FireFox or IE 10+
  * Note: Progress bars are currently disabled in IE
  * Note: IE <= 9 users will be instructed to upgrade their browser upon
  selecting a file

## Demo

See a demo application using `s3_relay` [here](https://github.com/kjohnston/s3_relay-demo).

## Configuring CORS

Edit your S3 bucket's CORS Configuration to resemble the following:

```
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>POST</AllowedMethod>
    <AllowedHeader>Content-Type</AllowedHeader>
    <AllowedHeader>origin</AllowedHeader>
  </CORSRule>
</CORSConfiguration>
```

Note: The example above is a starting point for development.  Obviously, you
don't want to permit requests from any domain to upload to your S3 bucket.
Please see the [AWS Documentation](http://docs.aws.amazon.com/AmazonS3/latest/dev/cors.html)
to learn how to lock it down further.

## Installation

* Add `gem "s3_relay"` to your Gemfile and run `bundle`.
* Add migrations to your app with `rake s3_relay:install:migrations db:migrate`.
* Add `mount S3Relay::Engine => "/s3_relay"` to the top of your routes file.
* Add `require s3_relay` to your JavaScript manifest.
* [Optional] Add `require s3_relay` to your Style Sheet manifest.
* Add the following environment variables to your app:

```
S3_RELAY_ACCESS_KEY_ID="abc123"
S3_RELAY_SECRET_ACCESS_KEY="xzy456"
S3_RELAY_REGION="us-west-2"
S3_RELAY_BUCKET="some-s3-bucket"
S3_RELAY_ACL="private"
```

## Use

### Add upload definitions to your model

```ruby
class Product < ActiveRecord::Base
  s3_relay :icon_upload
  s3_relay :photo_uploads, has_many: true
end
```

### Restricting uploads to authenticated users

If your app's file uploads need to be restricted to logged in users, simply
override the following method in your application controller to call any
authentication method you're currently using.

```ruby
def authenticate_for_s3_relay
  authenticate_user!  # Devise example
end
```

### Add virtual attributes to your controller's Strong Parameters config

```ruby
product_params = params.require(:product)
  .permit(:name, :new_icon_upload_uuids: [], new_photo_uploads_uuids: [])

@product = Product.new(product_params)
```

### Add file upload fields to your views

```erb
<%= s3_relay_field @product, :icon_upload %>
<%= s3_relay_field @product, :photo_uploads, multiple: true %>
```

* By default the content-disposition on the files stored in the uploads bucket
will be set to inline.  You can optionally set it to attachment by passing that
option like so:

```erb
<%= s3_relay_field @artist, :mp3_uploads, multiple: true, disposition: "attachment" %>
```

### Importing files

#### Processing uploads asynchronously

Use your background job processor of choice to process uploads pending
ingestion (and image processing) by your app.

Say you're using [Resque](https://github.com/resque/resque) and [CarrierWave](https://github.com/carrierwaveuploader/carrierwave), you could define a job class:

```ruby
class ProductPhoto::Import
  @queue = :photo_import

  def self.perform(product_id, upload_id)
    @product = Product.find(product_id)
    @upload  = S3Relay::Upload.find(upload_id)

    @product.photos.create!(remote_file_url: @upload.private_url)
    @upload.mark_imported!
  end
end
```

#### Triggering upload imports for existing parent objects

If you would like to immediately enqueue a job to begin importing an upload
into its final desination, simply define a method on your parent object
called `import_upload` and that method will be called after an `S3Relay::Upload`
is created.

#### Triggering upload imports for new parent objects

If you would like to immediately enqueue a job to begin importing all of the
uploads for a new parent object following its creation, you might want to setup
a callback to enqueue those imports.

#### Examples

```ruby
class Product

  # Called by s3_relay when an associated S3Relay::Upload object is created
  def import_upload(upload_id)
    Resque.enqueue(ProductPhoto::Import, id, upload_id)
  end

  after_commit :import_uploads, on: :create

  # Called via after_commit to enqueue imports of S3Relay::Upload objects
  def import_uploads
    photo_uploads.pending.each do |upload|
      Resque.enqueue(ProductPhoto::Import, id, upload.id)
    end
  end

end
```

### Restricting the objects uploads can be associated with

Remember the time when that guy found a way to a submit Github form in such a
way that it linked a new SSH key he provided to DHH's user record?  No bueno.
Don't let your users attach files to objects they don't have access to.

You can prevent this by defining a method in ApplicationController that
filters out the parent object params passed during upload creation if your logic
finds that the user doesn't have access to the parent object in question.  Ex:

```ruby
def order_file_uploads_params(parent)
  if parent.user == current_user
    # Yep, that's your order, you can add files to it
    { parent: parent }
  else
    # Nope, you're trying to add a file to someone else's order, or whatever
    { }
  end
end
```

## Contributing

1. [Fork it](https://github.com/kjohnston/s3_relay/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. [Create a Pull Request](https://github.com/kjohnston/s3_relay/pull/new)

## License

* Freely distributable and licensed under the [MIT license](http://kjohnston.mit-license.org/license.html).
* Copyright (c) 2014 Kenny Johnston
