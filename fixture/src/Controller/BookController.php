<?php

namespace App\Controller;

use App\Entity\Book;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

class BookController
{
    #[Route('/books', name: 'book_list', methods: ['GET'])]
    public function list(EntityManagerInterface $em): JsonResponse
    {
        $books = $em->getRepository(Book::class)->findAll();

        $data = [];
        foreach ($books as $book) {
            $data[] = [
                'title' => $book->getTitle(),
                'author' => $book->getAuthor()->getName(),
            ];
        }

        return new JsonResponse($data);
    }
}
