#!/usr/bin/env ruby
begin
  require 'RMagick'
rescue LoadError
  require 'rubygems'
  
  begin
    require 'RMagick'
  rescue LoadError
    puts "RMagick is required to run this script:"
    puts "'gem install rmagick'"
    exit
  end    
end  

def write_image(name, width, height, pixels = nil)
  puts "Writing image #{name} - #{width}x#{height}"
  img = Magick::Image.new(width, height)
  img.store_pixels(0, 0, width, height, pixels) if pixels
  img.write(name)
end

def parse_slices(img, shreds, size)
  slices   = []  
  borders  = []
  x_offset = 0
  y_offset = 0
    
  (0..(shreds - 1)).each do |n|  

    # Start at end of previous slice
    # Get the full height of image + width of 1 slice
    x_offset  = n * size
    slices[n] = img.get_pixels(x_offset, y_offset, size, img.rows)

    # Write out individual slices
    #write_image("slice#{n}.png", shred_size, rows, slices[n])

    # Setup border hash for this slice
    borders[n] = {:left => [], :right => []}  

    slices[n].each_with_index do |pixel, i|
      if i % size == 0
        # Pixel is on far left of slice
        borders[n][:left] << pixel
      elsif i % size == size-1
        # Pixel is on far right of slice  
        borders[n][:right] << pixel
      end      
    end    
  end
  
  return slices, borders
end  

def border_scores(borders)
  scores = []
  borders.each_with_index do |border, i|
    scores[i] = {:left => [], :right => []}

    border[:right].each_with_index do |right, pixel|    
      borders.each_with_index do |b, n|
        scores[i][:right][n] ||= 0

        unless n == i
          left = b[:left][pixel]

          red   = (right.red   - left.red).abs
          green = (right.green - left.green).abs
          blue  = (right.blue  - left.blue).abs

          scores[i][:right][n] += (red + green + blue)      
        end  
      end  
    end 

    border[:left].each_with_index do |left, pixel|    
      borders.each_with_index do |b, n|  
        scores[i][:left][n] ||= 0

        unless n == i
          right = b[:right][pixel]
          
          red   = (right.red   - left.red).abs
          green = (right.green - left.green).abs
          blue  = (right.blue  - left.blue).abs

          scores[i][:left][n] += (red + green + blue)
        end  
      end  
    end 
  end
  
  return scores
end  


# Override CLI
file = nil
# file = '/Users/bmckim/Desktop/tokyo_flipped.png'

if ARGV[0]
  file = ARGV[0]  
elsif !file
  puts "Please provide a path to an image file."
  exit
end  

begin
  img  = Magick::Image::read(file).first
rescue Magick::ImageMagickError
  puts "Did you enter a path to a valid image file?"
  exit
end

cols        = img.columns
rows        = img.rows
shred_size  = 32
shreds      = cols / shred_size

puts "Detecting Shreds..."
slices, borders = parse_slices(img, shreds, shred_size)

puts "Calculating scores..."
# Scores for each border compared per pixel
scores = border_scores(borders)

puts "Pairing up shreds..."
# Get the neighbors with lowest scores.
# Chose the shred at index 1 because index 0 its itself.
neighbors = []
scores.each_with_index do |score, i|
  neighbors[i] = {}  
  
  left_score  = score[:left].sort[1]
  left_shred  = score[:left].index(left_score)
  right_score = score[:right].sort[1]
  right_shred = score[:right].index(right_score)
  
  neighbors[i][:right] = { :shred => right_shred, :score => right_score }
  neighbors[i][:left]  = { :shred => left_shred,  :score => left_score  }
end  

# Detect which shreds are on the photos edge by checking for dupes.
# Dupe with higher score is probably incorrect neighbor.
left_dupes  = []  
right_dupes = []

neighbors.each do |neighbor|
  left_dupes  << neighbor if neighbors.select { |n| n[:left][:shred]  == neighbor[:left][:shred]  }.size > 1
  right_dupes << neighbor if neighbors.select { |n| n[:right][:shred] == neighbor[:right][:shred] }.size > 1
end  

right_border = nil
left_border  = nil

unless left_dupes.empty?
  if left_dupes[0][:left][:score] < left_dupes[1][:left][:score]
    left_border = neighbors[neighbors.index(left_dupes[1])]
  else
    left_border = neighbors[neighbors.index(left_dupes[0])]
  end    
  
  left_border[:left] = nil
end

unless right_dupes.empty?
  if right_dupes[0][:right][:score] < right_dupes[1][:right][:score]
    right_border = neighbors[neighbors.index(right_dupes[1])]
  else
    right_border = neighbors[neighbors.index(right_dupes[0])]
  end
  
  right_border[:right] = nil
end    

puts "Arranging..."
order = []
if left_border
  puts "Constructing from the left."
  order += [neighbors.index(left_border), left_border[:right][:shred]]

  x = 0
  while(x < shreds - 2) do
    next_shred = nil
    next_shred = neighbors.select { |n|  n[:left][:shred] == order.last if n[:left] }.first
    order.push(neighbors.index(next_shred)) if next_shred    
    x += 1
  end
    
elsif right_border
  puts "Constructing from the right."
  order += [right_border[:left][:shred], neighbors.index(right_border)]
  
  x = 0
  while(x < shreds - 2) do
    next_shred = nil
    next_shred = neighbors.select { |n|  n[:right][:shred] == order.first if n[:right] }.first
    order.unshift(neighbors.index(next_shred)) if next_shred    
    x += 1
  end
end    

puts "Reconstructing..."
# Reconstruct 1 row at a time per slice.
# Better way to do this?  
spliced_pixels = []
(0..rows-1).each do |row|
  pixel_offset = row * 32

  order.each do |slice|    
    spliced_pixels += slices[slice][pixel_offset..pixel_offset+shred_size-1]
  end
end

extension = /\.\w*$/.match(file).to_s
write_image("#{file.gsub(extension, '')}_unshredded#{extension}", cols, rows, spliced_pixels)
